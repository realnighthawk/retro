package engine

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"
)

type SuggestInput struct {
	Day                        string   `json:"day"`
	Occasion                   string   `json:"occasion,omitempty"`
	Warmth                     string   `json:"warmth,omitempty"`
	RequiredIDs                []string `json:"required_ids,omitempty"`
	ExcludedIDs                []string `json:"excluded_ids,omitempty"`
	ExcludedCombinations       []string `json:"excluded_combinations,omitempty"`
	Variant                    int      `json:"variant,omitempty"`
	ExpectedPreferencesVersion *int64   `json:"expected_preferences_version,omitempty"`
	SwapRole                   string   `json:"swap_role,omitempty"`
	// TemperatureC is the value ranking should use, in Celsius: the owner's own reading or a forecast
	// the client already reviewed. Ranking is never given a temperature nobody stated.
	TemperatureC *int `json:"temperature_c,omitempty"`
	// Precipitation records that rain or snow was reported. No garment records water resistance, so it
	// can only be disclosed as unassessed, never filtered on.
	Precipitation *bool `json:"precipitation,omitempty"`
}
type SuggestedItem struct {
	Selection
	Version int64  `json:"version"`
	Name    string `json:"name,omitempty"`
}
type Suggestion struct {
	Items        []SuggestedItem `json:"items"`
	Fingerprint  string          `json:"fingerprint"`
	Reasons      []string        `json:"reasons"`
	MissingRoles []string        `json:"missing_roles"`
	Score        int             `json:"score"`
}
type Suggestions struct {
	Day               string        `json:"day"`
	Algorithm         string        `json:"algorithm"`
	GeneratedAt       time.Time     `json:"generated_at"`
	Items             []Suggestion  `json:"items"`
	NoResultReason    *string       `json:"no_result_reason"`
	EffectiveOccasion string        `json:"effective_occasion"`
	PreferencesSource ContextSource `json:"preferences_source"`
	FeedbackSamples   int           `json:"feedback_samples"`
	FeedbackCoverage  string        `json:"feedback_coverage"`
	Warnings          []string      `json:"warnings"`
}

type ratedOutfit struct {
	IDs []string
	FeedbackData
}
type ratingTotal struct{ sum, count, wears int }

func (r ratingTotal) points() int {
	if r.count == 0 {
		return 0
	}
	return 2 * r.sum / r.count
}
func feedbackTotals(wears []ratedOutfit) (map[string]ratingTotal, map[string]ratingTotal) {
	pieces, looks := map[string]ratingTotal{}, map[string]ratingTotal{}
	for _, wear := range wears {
		total := ratingTotal{}
		for _, rating := range []*int{wear.Rating, wear.StyleRating, wear.ComfortRating} {
			if rating != nil {
				total.sum += *rating - 3
				total.count++
			}
		}
		if total.count == 0 {
			continue
		}
		items := []SuggestedItem{}
		for _, key := range wear.IDs {
			r := pieces[key]
			r.sum += total.sum
			r.count += total.count
			r.wears++
			pieces[key] = r
			items = append(items, SuggestedItem{Selection: Selection{GarmentID: key}})
		}
		key := fingerprint(items)
		r := looks[key]
		r.sum += total.sum
		r.count += total.count
		r.wears++
		looks[key] = r
	}
	return pieces, looks
}
func matches(values, wanted []string) bool {
	for _, a := range values {
		for _, b := range wanted {
			if strings.EqualFold(strings.TrimSpace(a), strings.TrimSpace(b)) {
				return true
			}
		}
	}
	return false
}

// temperatureBand places a stated temperature against the owner's own thresholds.
func temperatureBand(temperature, cold, hot int) string {
	switch {
	case temperature <= cold:
		return "cold"
	case temperature >= hot:
		return "hot"
	}
	return "mild"
}
func temperatureWeight(sensitivity string) int {
	switch sensitivity {
	case "low":
		return 2
	case "high":
		return 7
	}
	return 4
}

// warmthFit scores a garment's recorded warmth against the band. An unknown warmth is never treated as
// wrong: it scores nothing and says so, because a missing tag is not evidence of the wrong layer.
func warmthFit(band, warmth string, weight int) (int, string) {
	if warmth == "" || warmth == "unknown" {
		return 0, ""
	}
	wanted, unwanted := "mid", ""
	switch band {
	case "cold":
		wanted, unwanted = "warm", "light"
	case "hot":
		wanted, unwanted = "light", "warm"
	case "mild":
		unwanted = ""
	}
	switch warmth {
	case wanted:
		return weight, "its " + warmth + " warmth suits a " + band + " day."
	case unwanted:
		return -weight, "its " + warmth + " warmth is the wrong side of a " + band + " day."
	}
	return 0, ""
}

func garmentRank(g Garment, in SuggestInput, p PreferencesData, feedback ratingTotal) (int, []string) {
	score, reasons := 0, []string{}
	add := func(points int, reason string) { score += points; reasons = append(reasons, g.Name+": "+reason) }
	if in.Warmth != "" && g.Warmth == in.Warmth {
		add(8, "matches the requested warmth tag.")
	}
	if in.TemperatureC != nil {
		band := temperatureBand(*in.TemperatureC, p.ColdThresholdC, p.HotThresholdC)
		// A missing warmth tag stays neutral and is reported in the response warning instead, so it
		// cannot crowd out the real reasons on a garment.
		if points, reason := warmthFit(band, g.Warmth, temperatureWeight(p.TemperatureSensitivity)); reason != "" {
			add(points, fmt.Sprintf("%s %d°C is a %s day for your thresholds.", reason, *in.TemperatureC, band))
		}
	}
	if in.Occasion != "" && strings.EqualFold(g.Formality, in.Occasion) {
		add(6, "matches the occasion/formality tag.")
	}
	if matches(g.Colours, p.PreferredColours) {
		add(4, "matches a preferred colour.")
	}
	if matches([]string{g.Formality}, p.PreferredStyles) {
		add(3, "its formality tag matches a preferred style.")
	}
	if p.PreferUnderusedItems {
		points := 0
		switch {
		case g.WearDays == 0:
			points = 5
		case g.WearDays <= 3:
			points = 3
		case g.WearDays <= 10:
			points = 1
		}
		if points > 0 {
			add(points, fmt.Sprintf("underused, with %d confirmed wear days through this date.", g.WearDays))
		}
	}
	if g.Favourite {
		add(1, "marked as a favourite.")
	}
	if feedback.count > 0 {
		add(feedback.points(), fmt.Sprintf("appeared in %d explicitly rated wears (ranking contribution %+d).", feedback.wears, feedback.points()))
	}
	return score, reasons
}
func dailyTie(day, key string) string {
	hash := sha256.Sum256([]byte(day + "\n" + key))
	return hex.EncodeToString(hash[:])
}

func role(g Garment) string {
	switch g.Category {
	case "top":
		if oneOf(strings.ToLower(g.Subtype), "sweater", "cardigan", "hoodie") {
			return "mid"
		}
		return "base"
	case "bottom":
		return "bottom"
	case "one_piece":
		return "one_piece"
	case "outerwear":
		return "outer"
	case "footwear":
		return "feet"
	case "accessory":
		return "accessory"
	}
	return "other"
}
func fingerprint(items []SuggestedItem) string {
	ids := []string{}
	for _, v := range items {
		ids = append(ids, v.GarmentID)
	}
	sort.Strings(ids)
	hash := sha256.Sum256([]byte(strings.Join(ids, "\n")))
	return hex.EncodeToString(hash[:])
}
func buildSuggestions(garments []Garment, in SuggestInput, p PreferencesData, wears []ratedOutfit) ([]Suggestion, error) {
	if e := date(in.Day); e != nil {
		return nil, e
	}
	if in.Variant < 0 || in.Variant > 1000 || len(in.RequiredIDs) > 10 || len(in.ExcludedIDs) > 100 || len(in.ExcludedCombinations) > 100 || len(in.Occasion) > 100 {
		return nil, invalid("suggestion input exceeds its limits")
	}
	if in.Warmth != "" && !oneOf(in.Warmth, "light", "mid", "warm") {
		return nil, invalid("unsupported warmth")
	}
	if in.SwapRole != "" && !oneOf(in.SwapRole, "base", "bottom", "one_piece", "mid", "outer", "feet", "accessory") {
		return nil, invalid("unsupported swap role")
	}
	if in.Occasion == "" {
		in.Occasion = p.DefaultOccasion
	}
	pieceFeedback, lookFeedback := feedbackTotals(wears)
	target, _ := time.Parse("2006-01-02", in.Day)
	excluded := map[string]bool{}
	for _, v := range in.ExcludedIDs {
		key, e := id(v)
		if e != nil {
			return nil, e
		}
		if excluded[key] {
			return nil, invalid("excluded_ids cannot repeat")
		}
		excluded[key] = true
	}
	required := map[string]bool{}
	for _, v := range in.RequiredIDs {
		key, e := id(v)
		if e != nil {
			return nil, e
		}
		if required[key] {
			return nil, invalid("required_ids cannot repeat")
		}
		required[key] = true
		if excluded[key] {
			return nil, invalid("a required garment cannot also be excluded")
		}
	}
	available := []Garment{}
	scores := map[string]int{}
	reasons := map[string][]string{}
	for _, g := range garments {
		if g.ArchivedAt != nil || g.Availability != "ready" || excluded[g.ID] || role(g) == "other" || matches(g.Colours, p.AvoidedColours) {
			continue
		}
		if p.AvoidRepeatDays > 0 && g.LastWornOn != nil {
			last, e := time.Parse("2006-01-02", *g.LastWornOn)
			if e != nil {
				return nil, invalid("garment wear date is invalid")
			}
			days := int(target.Sub(last).Hours() / 24)
			if days >= 0 && days < p.AvoidRepeatDays {
				continue
			}
		}
		scores[g.ID], reasons[g.ID] = garmentRank(g, in, p, pieceFeedback[g.ID])
		available = append(available, g)
	}
	sort.Slice(available, func(i, j int) bool {
		a, b := available[i], available[j]
		if scores[a.ID] != scores[b.ID] {
			return scores[a.ID] > scores[b.ID]
		}
		return dailyTie(in.Day, a.ID) < dailyTie(in.Day, b.ID)
	})
	choices := map[string][]Garment{}
	fixed := map[string]Garment{}
	found := map[string]bool{}
	for _, g := range available {
		r := role(g)
		if required[g.ID] {
			if _, exists := fixed[r]; exists {
				return nil, invalid("required pieces compete for the same role; compose manually")
			}
			fixed[r] = g
			found[g.ID] = true
		}
		if len(choices[r]) < 8 {
			choices[r] = append(choices[r], g)
		}
	}
	for key := range required {
		if !found[key] {
			return nil, conflict("a required garment is unavailable, excluded, conflicts with avoided colours/repeat settings or has no automatic role; review settings or compose manually")
		}
	}
	if _, one := fixed["one_piece"]; one {
		if _, base := fixed["base"]; base {
			return nil, invalid("one-piece and base garments conflict")
		}
		if _, bottom := fixed["bottom"]; bottom {
			return nil, invalid("one-piece and bottom garments conflict")
		}
	}
	for r, g := range fixed {
		choices[r] = []Garment{g}
	}
	if in.SwapRole != "" {
		if _, locked := fixed[in.SwapRole]; locked {
			return nil, invalid("unlock the requested swap role first")
		}
		if len(choices[in.SwapRole]) == 0 {
			return []Suggestion{}, nil
		}
	}
	blocked := map[string]bool{}
	for _, v := range in.ExcludedCombinations {
		hash, e := hex.DecodeString(v)
		if e != nil || len(hash) != 32 {
			return nil, invalid("excluded combinations must be SHA-256 fingerprints")
		}
		blocked[hex.EncodeToString(hash)] = true
	}
	less := func(a, b Suggestion) bool {
		if len(a.MissingRoles) != len(b.MissingRoles) {
			return len(a.MissingRoles) < len(b.MissingRoles)
		}
		if a.Score != b.Score {
			return a.Score > b.Score
		}
		return dailyTie(in.Day, a.Fingerprint) < dailyTie(in.Day, b.Fingerprint)
	}
	pool := []Suggestion{}
	_, fixedOne := fixed["one_piece"]
	_, fixedBase := fixed["base"]
	_, fixedBottom := fixed["bottom"]
	layouts := [][]string{}
	if !fixedOne && in.SwapRole != "one_piece" && (len(choices["base"]) > 0 || len(choices["bottom"]) > 0 || len(choices["one_piece"]) == 0) {
		layouts = append(layouts, []string{"base", "bottom"})
	}
	if len(choices["one_piece"]) > 0 && !fixedBase && !fixedBottom && !oneOf(in.SwapRole, "base", "bottom") {
		layouts = append(layouts, []string{"one_piece"})
	}
	for _, layout := range layouts {
		for _, layer := range []string{"mid", "outer"} {
			_, locked := fixed[layer]
			if locked || in.SwapRole == layer || p.LayeringPreference == "heavy" || (p.LayeringPreference == "moderate" && in.Warmth != "light" && (layer == "outer" || in.Warmth == "warm")) {
				layout = append(layout, layer)
			}
		}
		layout = append(layout, "feet", "accessory")
		beam := []Suggestion{{Items: []SuggestedItem{}, MissingRoles: []string{}}}
		// shortcut: eight garments per role and a 64-choice beam per layout; expand the search if owners exhaust these alternatives.
		for _, r := range layout {
			if len(choices[r]) == 0 {
				if oneOf(r, "base", "bottom", "one_piece", "feet") {
					for i := range beam {
						beam[i].MissingRoles = append(beam[i].MissingRoles, r)
					}
				}
				continue
			}
			next := []Suggestion{}
			for _, option := range beam {
				for _, g := range choices[r] {
					items := append(append([]SuggestedItem{}, option.Items...), SuggestedItem{Selection: Selection{g.ID, r}, Version: g.Version, Name: g.Name})
					next = append(next, Suggestion{Items: items, MissingRoles: option.MissingRoles, Score: option.Score + scores[g.ID], Fingerprint: fingerprint(items)})
				}
			}
			sort.Slice(next, func(i, j int) bool { return less(next[i], next[j]) })
			if len(next) > 64 {
				next = next[:64]
			}
			beam = next
		}
		for _, option := range beam {
			if len(option.Items) == 0 {
				continue
			}
			option.Fingerprint = fingerprint(option.Items)
			if blocked[option.Fingerprint] {
				continue
			}
			option.Score += 2 * lookFeedback[option.Fingerprint].points()
			pool = append(pool, option)
		}
	}
	sort.Slice(pool, func(i, j int) bool { return less(pool[i], pool[j]) })
	result := []Suggestion{}
	if len(pool) == 0 {
		return result, nil
	}
	start := in.Variant % len(pool)
	pool = append(pool[start:], pool[:start]...)
	diversity := map[string]int{"low": 0, "moderate": 2, "high": 4}[p.Variety]
	used := map[string]int{}
	for len(pool) > 0 && len(result) < 3 {
		best := 0
		adjusted := func(option Suggestion) int {
			score := option.Score
			for _, item := range option.Items {
				score -= diversity * used[item.GarmentID]
			}
			return score
		}
		for i := range pool {
			if len(pool[i].MissingRoles) < len(pool[best].MissingRoles) || (len(result) > 0 && len(pool[i].MissingRoles) == len(pool[best].MissingRoles) && adjusted(pool[i]) > adjusted(pool[best])) {
				best = i
			}
		}
		option := pool[best]
		pool = append(pool[:best], pool[best+1:]...)
		option.Reasons = []string{"Only active, ready garments are included; avoided colours and the saved repeat interval are enforced.", "Your layering preference is " + p.LayeringPreference + "; locked or explicitly swapped layers are kept."}
		for _, item := range option.Items {
			option.Reasons = append(option.Reasons, reasons[item.GarmentID]...)
			used[item.GarmentID]++
		}
		if lookFeedback[option.Fingerprint].count > 0 {
			option.Reasons = append(option.Reasons, fmt.Sprintf("This exact combination has explicit rated-wear history (ranking contribution %+d).", 2*lookFeedback[option.Fingerprint].points()))
		}
		result = append(result, option)
	}
	return result, nil
}
func suggest(ctx context.Context, u *unit, in SuggestInput) (Suggestions, error) {
	result := Suggestions{Day: in.Day, Algorithm: "rules-v2", GeneratedAt: time.Now().UTC(), Items: []Suggestion{},
		FeedbackCoverage: "latest_2000_version_matched_rated_wears_through_requested_day",
		Warnings:         []string{"Styles match saved formality tags only; unknown style is not inferred.", "Temperature is used only when it is supplied and only against recorded warmth tags; weather beyond that, care compatibility and scheduled delivery are not assessed."}}
	if in.TemperatureC == nil {
		result.Warnings = append(result.Warnings, "No temperature was supplied, so warmth was not matched to the weather.")
	} else if *in.TemperatureC < -60 || *in.TemperatureC > 60 {
		return result, invalid("temperature_c must be between -60 and 60")
	}
	if in.Precipitation != nil && *in.Precipitation {
		result.Warnings = append(result.Warnings, "Rain or snow was reported, but no garment records water resistance, so nothing was filtered or scored for it.")
	}
	if e := date(in.Day); e != nil {
		return result, e
	}
	p, e := u.getPreferences(ctx)
	if e != nil {
		return result, e
	}
	if in.ExpectedPreferencesVersion != nil {
		if e := version(*in.ExpectedPreferencesVersion, p.Version); e != nil {
			return result, e
		}
	}
	result.PreferencesSource = ContextSource{EntityType: "preferences", ID: p.ID, Version: p.Version, UpdatedAt: &p.UpdatedAt}
	result.EffectiveOccasion = in.Occasion
	if result.EffectiveOccasion == "" {
		result.EffectiveOccasion = p.DefaultOccasion
	}
	// shortcut: suggestions cap at 2000 garments; add a bulk shortlist for larger wardrobes.
	rows, e := u.tx.Query(ctx, `SELECT `+garmentJSON+`,COALESCE(w.days,0),COALESCE(w.events,0),w.last_day
		FROM retro.garments g LEFT JOIN (
		 SELECT i.garment_id,count(DISTINCT o.day) AS days,count(*) AS events,max(o.day)::text AS last_day
		 FROM retro.outfit_items i JOIN retro.outfits o ON o.id=i.outfit_id
		 WHERE o.state='worn' AND o.day <= $1::date GROUP BY i.garment_id
		) w ON w.garment_id=g.id ORDER BY g.id LIMIT 2001`, in.Day)
	if e != nil {
		return result, e
	}
	garments := []Garment{}
	for rows.Next() {
		var g Garment
		var raw []byte
		if e = rows.Scan(&raw, &g.WearDays, &g.WearEvents, &g.LastWornOn); e != nil {
			rows.Close()
			return result, e
		}
		if e = json.Unmarshal(raw, &g); e != nil {
			rows.Close()
			return result, e
		}
		garments = append(garments, g)
	}
	e = rows.Err()
	rows.Close()
	if e != nil {
		return result, e
	}
	if len(garments) > 2000 {
		return result, invalid("automatic suggestions support up to 2000 garments; compose manually")
	}
	if in.TemperatureC != nil {
		unknown := 0
		for _, g := range garments {
			if g.Warmth == "" || g.Warmth == "unknown" {
				unknown++
			}
		}
		if unknown > 0 {
			result.Warnings = append(result.Warnings, fmt.Sprintf("%d of %d active garments have no warmth tag, so the temperature could not be matched to them.", unknown, len(garments)))
		}
	}
	feedbackRows, e := u.tx.Query(ctx, `SELECT array_agg(i.garment_id::text ORDER BY i.garment_id),f.attributes
		FROM retro.outfit_feedback f JOIN retro.outfits o ON o.id=f.outfit_id
		JOIN retro.outfit_items i ON i.outfit_id=o.id
		WHERE o.state='worn' AND o.day <= $1::date AND f.outfit_version=o.version
		 AND f.attributes ?| ARRAY['rating','style_rating','comfort_rating']
		GROUP BY o.id,f.id ORDER BY o.day DESC,o.id DESC LIMIT 2001`, in.Day)
	if e != nil {
		return result, e
	}
	wears := []ratedOutfit{}
	for feedbackRows.Next() {
		if len(wears) == 2000 {
			result.Warnings = append(result.Warnings, "Older rated wears are outside the 2000-wear feedback window.")
			break
		}
		var wear ratedOutfit
		var raw []byte
		if e = feedbackRows.Scan(&wear.IDs, &raw); e != nil {
			feedbackRows.Close()
			return result, e
		}
		if e = json.Unmarshal(raw, &wear.FeedbackData); e != nil {
			feedbackRows.Close()
			return result, e
		}
		wears = append(wears, wear)
	}
	e = feedbackRows.Err()
	feedbackRows.Close()
	if e != nil {
		return result, e
	}
	result.FeedbackSamples = len(wears)
	result.Items, e = buildSuggestions(garments, in, p.PreferencesData, wears)
	if len(result.Items) == 0 && e == nil {
		message := "No combination remains in the bounded search under current availability, avoided colours, repeat interval and exclusions. Review settings or compose manually; constraints were not relaxed."
		result.NoResultReason = &message
	}
	return result, e
}
