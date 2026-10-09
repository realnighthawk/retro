package engine

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"strconv"
)

func history(ctx context.Context, u *unit, in HistoryInput) (Page[Change], error) {
	result := Page[Change]{Items: []Change{}}
	key, e := id(in.ID)
	if e != nil {
		return result, e
	}
	if !oneOf(in.EntityType, "garment", "outfit", "media", "preferences", "feedback", "pairing", "day_selection", "daily_settings", "daily_run", "laundry_load") {
		return result, invalid("unsupported entity_type")
	}
	// History is only available for an existing record.
	switch in.EntityType {
	case "laundry_load":
		_, e = u.getLaundry(ctx, key)
	case "daily_settings":
		if key != DailySettingsID {
			return result, notFound()
		}
		_, e = u.getDailySettings(ctx)
	case "daily_run":
		var run *DailyRun
		run, e = u.getDailyRun(ctx, key)
		if e == nil && run == nil {
			return result, notFound()
		}
	case "garment":
		_, e = u.getGarment(ctx, key)
	case "outfit":
		_, e = u.getOutfit(ctx, key)
	case "media":
		_, e = u.getMedia(ctx, key)
	case "preferences":
		if key != PreferencesID {
			return result, notFound()
		}
		_, e = u.getPreferences(ctx)
	case "feedback":
		_, e = u.getFeedback(ctx, key)
	case "pairing":
		_, e = u.getPairing(ctx, key)
	case "day_selection":
		var day string
		e = u.tx.QueryRow(ctx, `SELECT day::text FROM retro.day_selections WHERE id=$1`, key).Scan(&day)
	}
	if e != nil {
		return result, e
	}
	limit := in.Limit
	if limit == 0 {
		limit = 50
	}
	if limit < 1 || limit > 200 {
		return result, invalid("limit must be 1-200")
	}
	before := int64(0)
	filters := in
	filters.ListInput = ListInput{}
	if in.Cursor != "" {
		raw, err := base64.RawURLEncoding.DecodeString(in.Cursor)
		var c struct {
			Scope string `json:"scope"`
			After string `json:"after"`
		}
		if err != nil || json.Unmarshal(raw, &c) != nil || c.Scope != scope(filters) {
			return result, invalid("cursor does not match this query")
		}
		before, e = strconv.ParseInt(c.After, 10, 64)
		if e != nil || before < 1 {
			return result, invalid("invalid cursor")
		}
	}
	rows, e := u.tx.Query(ctx, `SELECT id,actor_id,operation,before_data,after_data,occurred_at FROM retro.changes WHERE entity_type=$1 AND entity_id=$2 AND ($3=0 OR id<$3) ORDER BY id DESC LIMIT $4`, in.EntityType, key, before, limit+1)
	if e != nil {
		return result, e
	}
	defer rows.Close()
	for rows.Next() {
		var c Change
		if e = rows.Scan(&c.ID, &c.Actor, &c.Operation, &c.Before, &c.After, &c.OccurredAt); e != nil {
			return result, e
		}
		result.Items = append(result.Items, c)
	}
	if e = rows.Err(); e != nil {
		return result, e
	}
	if len(result.Items) > limit {
		result.Items = result.Items[:limit]
		result.NextCursor = cursor(filters, strconv.FormatInt(result.Items[limit-1].ID, 10))
	}
	return result, nil
}

type AnalyzeInput struct {
	From string `json:"from,omitempty"`
	To   string `json:"to,omitempty"`
}
type CategoryUsage struct {
	Category     string `json:"category"`
	Garments     int64  `json:"garments"`
	WornGarments int64  `json:"worn_garments"`
	WearEvents   int64  `json:"wear_events"`
}
type Analysis struct {
	From           string          `json:"from,omitempty"`
	To             string          `json:"to,omitempty"`
	OutfitEvents   int64           `json:"outfit_events"`
	WearDays       int64           `json:"wear_days"`
	Garments       int64           `json:"garments"`
	UnwornGarments int64           `json:"unworn_garments"`
	Categories     []CategoryUsage `json:"categories"`
}

func analyze(ctx context.Context, u *unit, in AnalyzeInput) (Analysis, error) {
	result := Analysis{From: in.From, To: in.To, Categories: []CategoryUsage{}}
	if in.From != "" {
		if e := date(in.From); e != nil {
			return result, e
		}
	}
	if in.To != "" {
		if e := date(in.To); e != nil {
			return result, e
		}
	}
	if in.From != "" && in.To != "" && in.From > in.To {
		return result, invalid("from must not exceed to")
	}
	e := u.tx.QueryRow(ctx, `SELECT count(*),count(DISTINCT day) FROM retro.outfits WHERE state='worn' AND ($1='' OR day>=NULLIF($1,'')::date) AND ($2='' OR day<=NULLIF($2,'')::date)`, in.From, in.To).Scan(&result.OutfitEvents, &result.WearDays)
	if e != nil {
		return result, e
	}
	rows, e := u.tx.Query(ctx, `WITH usage AS (SELECT i.garment_id,count(*) events FROM retro.outfit_items i JOIN retro.outfits o ON o.id=i.outfit_id WHERE o.state='worn' AND ($1='' OR o.day>=NULLIF($1,'')::date) AND ($2='' OR o.day<=NULLIF($2,'')::date) GROUP BY i.garment_id)
 SELECT g.category,count(*),count(usage.garment_id),coalesce(sum(usage.events),0)::bigint FROM retro.garments g LEFT JOIN usage ON g.id=usage.garment_id GROUP BY g.category ORDER BY g.category`, in.From, in.To)
	if e != nil {
		return result, e
	}
	defer rows.Close()
	for rows.Next() {
		var c CategoryUsage
		if e = rows.Scan(&c.Category, &c.Garments, &c.WornGarments, &c.WearEvents); e != nil {
			return result, e
		}
		result.Categories = append(result.Categories, c)
		result.Garments += c.Garments
		result.UnwornGarments += c.Garments - c.WornGarments
	}
	return result, rows.Err()
}
