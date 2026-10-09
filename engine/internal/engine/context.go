package engine

import (
	"context"
	"encoding/json"
	"time"
)

type ContextInput struct {
	RequestID  string   `json:"request_id"`
	GarmentIDs []string `json:"garment_ids,omitempty"`
	OutfitIDs  []string `json:"outfit_ids,omitempty"`
}
type ContextSource struct {
	EntityType string     `json:"entity_type"`
	ID         string     `json:"id"`
	Version    int64      `json:"version"`
	UpdatedAt  *time.Time `json:"updated_at,omitempty"`
}
type WardrobeContext struct {
	SchemaVersion int              `json:"schema_version"`
	RequestID     string           `json:"request_id"`
	RetrievedAt   time.Time        `json:"retrieved_at"`
	Coverage      string           `json:"coverage"`
	Capabilities  []string         `json:"capabilities"`
	Preferences   Preferences      `json:"preferences"`
	Garments      []Garment        `json:"garments"`
	Outfits       []Outfit         `json:"outfits"`
	Feedback      []FeedbackResult `json:"feedback"`
	Sources       []ContextSource  `json:"sources"`
}

func contextIDs(values []string, limit int) ([]string, error) {
	if len(values) > limit {
		return nil, invalid("context exceeds its record limit")
	}
	seen := map[string]bool{}
	keys := []string{}
	for _, value := range values {
		key, e := id(value)
		if e != nil {
			return nil, e
		}
		if seen[key] {
			return nil, invalid("context IDs must be unique")
		}
		seen[key] = true
		keys = append(keys, key)
	}
	return keys, nil
}

func readContext(ctx context.Context, u *unit, in ContextInput) (WardrobeContext, error) {
	r := WardrobeContext{SchemaVersion: 1, RetrievedAt: time.Now().UTC(), Coverage: "explicit_records_only", Capabilities: []string{"wardrobe_records", "preferences", "care", "feedback"}, Garments: []Garment{}, Outfits: []Outfit{}, Feedback: []FeedbackResult{}, Sources: []ContextSource{}}
	key, e := id(in.RequestID)
	if e != nil {
		return r, e
	}
	r.RequestID = key
	garments, e := contextIDs(in.GarmentIDs, 10)
	if e != nil {
		return r, e
	}
	outfits, e := contextIDs(in.OutfitIDs, 5)
	if e != nil {
		return r, e
	}
	r.Preferences, e = u.getPreferences(ctx)
	if e != nil {
		return r, e
	}
	r.Sources = append(r.Sources, ContextSource{EntityType: "preferences", ID: r.Preferences.ID, Version: r.Preferences.Version, UpdatedAt: &r.Preferences.UpdatedAt})
	for _, key := range garments {
		g, e := u.getGarment(ctx, key)
		if e != nil {
			return r, e
		}
		r.Garments = append(r.Garments, g)
		r.Sources = append(r.Sources, ContextSource{EntityType: "garment", ID: g.ID, Version: g.Version, UpdatedAt: &g.UpdatedAt})
	}
	for _, key := range outfits {
		o, e := u.getOutfit(ctx, key)
		if e != nil {
			return r, e
		}
		f, e := readFeedback(ctx, u, GetInput{ID: key})
		if e != nil {
			return r, e
		}
		r.Outfits = append(r.Outfits, o)
		r.Feedback = append(r.Feedback, f)
		r.Sources = append(r.Sources, ContextSource{EntityType: "outfit", ID: o.ID, Version: o.Version, UpdatedAt: &o.UpdatedAt}, ContextSource{EntityType: "feedback", ID: f.Feedback.ID, Version: f.Feedback.Version, UpdatedAt: f.Feedback.UpdatedAt})
	}
	encoded, e := json.Marshal(r)
	if e != nil {
		return r, e
	}
	if len(encoded) > 128*1024 {
		return r, invalid("context exceeds 128 KiB; request fewer records")
	}
	return r, nil
}
