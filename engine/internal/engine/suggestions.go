package engine

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"sort"
	"strings"
	"time"
)

type SuggestInput struct {
	Day                  string   `json:"day"`
	Occasion             string   `json:"occasion,omitempty"`
	Warmth               string   `json:"warmth,omitempty"`
	RequiredIDs          []string `json:"required_ids,omitempty"`
	ExcludedIDs          []string `json:"excluded_ids,omitempty"`
	ExcludedCombinations []string `json:"excluded_combinations,omitempty"`
	Variant              int      `json:"variant,omitempty"`
}
type SuggestedItem struct {
	Selection
	Version int64 `json:"version"`
}
type Suggestion struct {
	Items        []SuggestedItem `json:"items"`
	Fingerprint  string          `json:"fingerprint"`
	Reasons      []string        `json:"reasons"`
	MissingRoles []string        `json:"missing_roles"`
}
type Suggestions struct {
	Day            string       `json:"day"`
	Algorithm      string       `json:"algorithm"`
	GeneratedAt    time.Time    `json:"generated_at"`
	Items          []Suggestion `json:"items"`
	NoResultReason *string      `json:"no_result_reason"`
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
func buildSuggestions(garments []Garment, in SuggestInput) ([]Suggestion, error) {
	if e := date(in.Day); e != nil {
		return nil, e
	}
	if in.Variant < 0 || in.Variant > 1000 || len(in.RequiredIDs) > 10 || len(in.ExcludedIDs) > 100 || len(in.ExcludedCombinations) > 100 || len(in.Occasion) > 100 {
		return nil, invalid("suggestion input exceeds its limits")
	}
	if in.Warmth != "" && !oneOf(in.Warmth, "light", "mid", "warm") {
		return nil, invalid("unsupported warmth")
	}
	excluded := map[string]bool{}
	for _, v := range in.ExcludedIDs {
		key, e := id(v)
		if e != nil {
			return nil, e
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
	}
	available := []Garment{}
	for _, g := range garments {
		if g.ArchivedAt == nil && g.Availability == "ready" && !excluded[g.ID] && role(g) != "other" {
			available = append(available, g)
		}
	}
	sort.Slice(available, func(i, j int) bool {
		a, b := available[i], available[j]
		if in.Warmth != "" && (a.Warmth == in.Warmth) != (b.Warmth == in.Warmth) {
			return a.Warmth == in.Warmth
		}
		if in.Occasion != "" && (a.Formality == in.Occasion) != (b.Formality == in.Occasion) {
			return a.Formality == in.Occasion
		}
		if (a.LastWornOn == nil) != (b.LastWornOn == nil) {
			return a.LastWornOn == nil
		}
		if a.LastWornOn != nil && *a.LastWornOn != *b.LastWornOn {
			return *a.LastWornOn < *b.LastWornOn
		}
		if a.Favourite != b.Favourite {
			return a.Favourite
		}
		return a.ID < b.ID
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
			return nil, conflict("a required garment is archived, unavailable, excluded or has no automatic role")
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
	blocked := map[string]bool{}
	for _, v := range in.ExcludedCombinations {
		hash, e := hex.DecodeString(v)
		if e != nil || len(hash) != 32 {
			return nil, invalid("excluded combinations must be SHA-256 fingerprints")
		}
		blocked[hex.EncodeToString(hash)] = true
	}
	result := []Suggestion{}
	seen := map[string]bool{}
	for n := in.Variant; n < in.Variant+128 && len(result) < 3; n++ {
		onePiece := len(choices["one_piece"]) > 0 && (len(choices["base"]) == 0 || n%2 == 1)
		if _, yes := fixed["one_piece"]; yes {
			onePiece = true
		}
		if _, yes := fixed["base"]; yes {
			onePiece = false
		}
		if _, yes := fixed["bottom"]; yes {
			onePiece = false
		}
		roles := []string{"base", "mid", "bottom", "outer", "feet", "accessory"}
		if onePiece {
			roles = []string{"one_piece", "mid", "outer", "feet", "accessory"}
		}
		option := Suggestion{Items: []SuggestedItem{}, Reasons: []string{"Only active, available garments are included."}, MissingRoles: []string{}}
		index := n
		_, fixedOne := fixed["one_piece"]
		_, fixedBase := fixed["base"]
		_, fixedBottom := fixed["bottom"]
		if len(choices["one_piece"]) > 0 && len(choices["base"]) > 0 && !fixedOne && !fixedBase && !fixedBottom {
			index = n / 2
		}
		for _, r := range roles {
			list := choices[r]
			if len(list) == 0 {
				if oneOf(r, "base", "bottom", "one_piece", "feet") {
					option.MissingRoles = append(option.MissingRoles, r)
				}
				continue
			}
			g := list[index%len(list)]
			index /= len(list)
			option.Items = append(option.Items, SuggestedItem{Selection{g.ID, r}, g.Version})
		}
		if len(option.Items) == 0 {
			continue
		}
		option.Fingerprint = fingerprint(option.Items)
		if seen[option.Fingerprint] || blocked[option.Fingerprint] {
			continue
		}
		seen[option.Fingerprint] = true
		option.Reasons = append(option.Reasons, "Prefers pieces worn less recently; favourites break ties.")
		if in.Warmth != "" {
			option.Reasons = append(option.Reasons, "Prioritizes garments tagged with your requested warmth: "+in.Warmth+".")
		}
		result = append(result, option)
	}
	return result, nil
}
func suggest(ctx context.Context, u *unit, in SuggestInput) (Suggestions, error) {
	result := Suggestions{Day: in.Day, Algorithm: "rules-v1", GeneratedAt: time.Now().UTC(), Items: []Suggestion{}}
	// shortcut: suggestions cap at 2000 garments, add a bulk ranking query before supporting larger wardrobes.
	rows, e := u.tx.Query(ctx, `SELECT id::text FROM retro.garments ORDER BY id LIMIT 2001`)
	if e != nil {
		return result, e
	}
	ids := []string{}
	for rows.Next() {
		var v string
		if e = rows.Scan(&v); e != nil {
			rows.Close()
			return result, e
		}
		ids = append(ids, v)
	}
	e = rows.Err()
	rows.Close()
	if e != nil {
		return result, e
	}
	if len(ids) > 2000 {
		return result, invalid("automatic suggestions support up to 2000 garments; compose manually")
	}
	garments := []Garment{}
	for _, v := range ids {
		g, e := u.getGarment(ctx, v)
		if e != nil {
			return result, e
		}
		garments = append(garments, g)
	}
	result.Items, e = buildSuggestions(garments, in)
	if len(result.Items) == 0 && e == nil {
		message := "No eligible combination remains; choose pieces manually or change the exclusions."
		result.NoResultReason = &message
	}
	return result, e
}
