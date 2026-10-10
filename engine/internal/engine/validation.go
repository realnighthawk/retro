package engine

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"github.com/google/uuid"
	"reflect"
	"strconv"
	"strings"
	"time"
)

func id(value string) (string, error) {
	parsed, err := uuid.Parse(value)
	if err != nil || parsed == uuid.Nil {
		return "", invalid("id must be a nonzero UUID")
	}
	return parsed.String(), nil
}
func createID(value string) (string, error) {
	if value == "" {
		return uuid.NewString(), nil
	}
	return id(value)
}
func oneOf(value string, allowed ...string) bool {
	for _, v := range allowed {
		if value == v {
			return true
		}
	}
	return false
}
func date(value string) error {
	t, e := time.Parse("2006-01-02", value)
	if e != nil || t.Format("2006-01-02") != value {
		return invalid("day must be YYYY-MM-DD")
	}
	return nil
}
func validateGarment(g *GarmentData) error {
	if e := validateLaundryReminder(g.LaundryReminder); e != nil {
		return e
	}
	if e := validateCare(g.Care); e != nil {
		return e
	}
	g.Name = strings.TrimSpace(g.Name)
	if len(g.Name) < 1 || len(g.Name) > 100 {
		return invalid("name must contain 1-100 bytes")
	}
	if !oneOf(g.Category, "top", "bottom", "one_piece", "outerwear", "footwear", "accessory", "other") {
		return invalid("unsupported category")
	}
	if g.Availability == "" {
		g.Availability = "ready"
	}
	if !oneOf(g.Availability, "ready", "needs_wash", "washing", "unavailable") {
		return invalid("unsupported availability")
	}
	if g.Warmth == "" {
		g.Warmth = "unknown"
	}
	if !oneOf(g.Warmth, "light", "mid", "warm", "unknown") {
		return invalid("unsupported warmth")
	}
	for _, text := range []string{g.Subtype, g.Formality, g.Material, g.Brand, g.Pattern, g.Style, g.Fit} {
		if len(text) > 100 {
			return invalid("attribute exceeds 100 bytes")
		}
	}
	if e := normalizePurchase(&g.Purchase); e != nil {
		return e
	}
	if len(g.Notes) > 4000 {
		return invalid("notes exceeds 4000 bytes")
	}
	for _, list := range [][]string{g.Colours, g.Seasons, g.MediaIDs} {
		if len(list) > 10 {
			return invalid("attribute list exceeds 10 entries")
		}
		seen := map[string]bool{}
		for _, v := range list {
			if strings.TrimSpace(v) == "" || len(v) > 100 || seen[v] {
				return invalid("attribute lists must contain unique nonempty values")
			}
			seen[v] = true
		}
	}
	seenMedia := map[string]bool{}
	for i, v := range g.MediaIDs {
		canonical, e := id(v)
		if e != nil {
			return e
		}
		g.MediaIDs[i] = canonical
		if seenMedia[canonical] {
			return invalid("media_ids cannot repeat")
		}
		seenMedia[canonical] = true
	}
	if g.Colours == nil {
		g.Colours = []string{}
	}
	if g.Seasons == nil {
		g.Seasons = []string{}
	}
	if g.MediaIDs == nil {
		g.MediaIDs = []string{}
	}
	return nil
}

// ISO 4217 exponents that differ from the usual two minor units; other codes use two.
// ponytail: a short table plus a two-decimal default, add a full ISO feed only if a real currency misreports.
var currencyExponents = map[string]int{
	"BIF": 0, "CLP": 0, "DJF": 0, "GNF": 0, "ISK": 0, "JPY": 0, "KMF": 0, "KRW": 0, "PYG": 0,
	"RWF": 0, "UGX": 0, "UYI": 0, "VND": 0, "VUV": 0, "XAF": 0, "XOF": 0, "XPF": 0,
	"BHD": 3, "IQD": 3, "JOD": 3, "KWD": 3, "LYD": 3, "OMR": 3, "TND": 3,
}

func currencyExponent(code string) int {
	if exponent, ok := currencyExponents[code]; ok {
		return exponent
	}
	return 2
}
func currencyCode(value string) bool {
	if len(value) != 3 {
		return false
	}
	for _, c := range value {
		if c < 'A' || c > 'Z' {
			return false
		}
	}
	return true
}

// parseAmount reads a plain decimal into minor units without floating point. Precision beyond the
// currency's exponent is rejected rather than rounded.
func parseAmount(value string, exponent int) (int64, error) {
	whole, fraction, _ := strings.Cut(value, ".")
	if whole == "" || len(fraction) > exponent {
		return 0, invalid("amount must be a plain decimal within the currency's minor units")
	}
	for _, c := range whole + fraction {
		if c < '0' || c > '9' {
			return 0, invalid("amount must be a plain decimal within the currency's minor units")
		}
	}
	digits := strings.TrimLeft(whole+fraction+strings.Repeat("0", exponent-len(fraction)), "0")
	if digits == "" {
		return 0, nil
	}
	if len(digits) > 15 {
		return 0, invalid("amount is out of range")
	}
	value64, e := strconv.ParseInt(digits, 10, 64)
	if e != nil || value64 > 999999999999999 {
		return 0, invalid("amount is out of range")
	}
	return value64, nil
}

// normalizePurchase validates an optional purchase record, deriving the amount and exponent and
// dropping an entirely empty record so clearing works through the ordinary patch.
func normalizePurchase(target **PurchaseRecord) error {
	if *target == nil {
		return nil
	}
	p := *target
	p.Date = strings.TrimSpace(p.Date)
	p.Currency = strings.ToUpper(strings.TrimSpace(p.Currency))
	p.Evidence = strings.TrimSpace(p.Evidence)
	p.Amount = strings.TrimSpace(p.Amount)
	if p.Source == "" {
		p.Source = "manual"
	}
	if !oneOf(p.Source, "manual", "receipt", "connected") {
		return invalid("unsupported purchase source")
	}
	if len(p.Evidence) > 2000 {
		return invalid("purchase evidence exceeds 2000 bytes")
	}
	if p.Source != "manual" && p.Evidence == "" {
		return invalid("a recorded purchase source requires bounded evidence")
	}
	if p.Date != "" {
		if e := date(p.Date); e != nil {
			return invalid("purchase date must be YYYY-MM-DD")
		}
	}
	if p.Currency != "" && !currencyCode(p.Currency) {
		return invalid("currency must be a three-letter ISO 4217 code")
	}
	if p.Amount != "" {
		if p.Currency == "" {
			return invalid("a purchase amount requires its currency")
		}
		minor, e := parseAmount(p.Amount, currencyExponent(p.Currency))
		if e != nil {
			return e
		}
		p.AmountMinor = &minor
	}
	p.Amount = ""
	if p.AmountMinor != nil && (*p.AmountMinor < 0 || *p.AmountMinor > 999999999999999) {
		return invalid("purchase amount is out of range")
	}
	if p.Currency == "" {
		p.CurrencyExponent = nil
	} else {
		exponent := currencyExponent(p.Currency)
		p.CurrencyExponent = &exponent
	}
	if p.Date == "" && p.Currency == "" && p.AmountMinor == nil && p.Evidence == "" && p.Source == "manual" {
		*target = nil
	}
	return nil
}
func validateOutfit(o *OutfitData, now time.Time) error {
	if e := date(o.Day); e != nil {
		return e
	}
	if o.TimeZone == "" || o.TimeZone == "Local" {
		return invalid("time_zone must be an explicit IANA timezone")
	}
	zone, e := time.LoadLocation(o.TimeZone)
	if e != nil {
		return invalid("time_zone must be an IANA timezone")
	}
	if !oneOf(o.State, "planned", "worn") {
		return invalid("state must be planned or worn")
	}
	if o.State == "worn" && o.Day > now.In(zone).Format("2006-01-02") {
		return invalid("a future outfit cannot be recorded as worn")
	}
	if len(o.Label) > 100 || len(o.Occasion) > 100 || len(o.Notes) > 4000 {
		return invalid("outfit text exceeds its limit")
	}
	if o.Source == "" {
		o.Source = "manual"
	}
	if !oneOf(o.Source, "manual", "suggestion", "agent") {
		return invalid("unsupported source")
	}
	return nil
}
func validateSelections(items []Selection) error {
	if len(items) < 1 || len(items) > 30 {
		return invalid("outfit must contain 1-30 garments")
	}
	seen := map[string]bool{}
	for i, v := range items {
		canonical, e := id(v.GarmentID)
		if e != nil {
			return e
		}
		items[i].GarmentID = canonical
		if seen[canonical] {
			return invalid("garments cannot repeat")
		}
		seen[canonical] = true
		if !oneOf(v.Role, "base", "mid", "bottom", "one_piece", "outer", "feet", "accessory", "other") {
			return invalid("unsupported outfit role")
		}
	}
	return nil
}
func patchFields(target any, patch map[string]json.RawMessage, allowed ...string) error {
	if len(patch) == 0 {
		return invalid("patch cannot be empty")
	}
	body, _ := json.Marshal(target)
	var fields map[string]json.RawMessage
	_ = json.Unmarshal(body, &fields)
	for k, v := range patch {
		if !oneOf(k, allowed...) {
			return invalid("unsupported patch field: " + k)
		}
		if bytes.Equal(bytes.TrimSpace(v), []byte("null")) {
			if oneOf(k, "name", "category", "availability", "favourite", "day", "time_zone") {
				return invalid("field cannot be null: " + k)
			}
			delete(fields, k)
		} else {
			fields[k] = v
		}
	}
	body, _ = json.Marshal(fields)
	value := reflect.ValueOf(target).Elem()
	value.Set(reflect.Zero(value.Type()))
	decoder := json.NewDecoder(bytes.NewReader(body))
	decoder.DisallowUnknownFields()
	if e := decoder.Decode(target); e != nil {
		return invalid("patch has invalid field types")
	}
	return nil
}

// page returns the limit, the record to continue after and that record's sort key. The key is
// empty for ID-ordered lists; sorted lists compare it as part of the keyset position.
func page(in ListInput, filters any) (int, string, string, error) {
	limit := in.Limit
	if limit == 0 {
		limit = 50
	}
	if limit < 1 || limit > 200 {
		return 0, "", "", invalid("limit must be 1-200")
	}
	if in.Cursor == "" {
		return limit, "", "", nil
	}
	raw, e := base64.RawURLEncoding.DecodeString(in.Cursor)
	if e != nil {
		return 0, "", "", invalid("invalid cursor")
	}
	var c struct {
		Scope string `json:"scope"`
		After string `json:"after"`
		Key   string `json:"key"`
	}
	if json.Unmarshal(raw, &c) != nil || c.Scope != scope(filters) {
		return 0, "", "", invalid("cursor does not match this query")
	}
	if _, e = id(c.After); e != nil {
		return 0, "", "", invalid("invalid cursor")
	}
	return limit, c.After, c.Key, nil
}
func scope(filters any) string {
	raw, _ := json.Marshal(filters)
	h := sha256.Sum256(raw)
	return hex.EncodeToString(h[:])
}
func cursor(filters any, after, key string) *string {
	raw, _ := json.Marshal(struct {
		Scope string `json:"scope"`
		After string `json:"after"`
		Key   string `json:"key,omitempty"`
	}{scope(filters), after, key})
	v := base64.RawURLEncoding.EncodeToString(raw)
	return &v
}
