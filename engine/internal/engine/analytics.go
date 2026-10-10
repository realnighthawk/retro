package engine

import (
	"context"
	"encoding/json"
	"time"
)

// Bounded lists: every capped list also reports its full count so a client can disclose coverage.
const (
	rankedLimit = 20
	unwornLimit = 50
	colourLimit = 100
	weekLimit   = 104
)

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

// CostPerWear divides one garment's recorded purchase amount by its confirmed wear events. It is
// never summed or converted across currencies, and it is absent when the price or the denominator
// is unknown: a garment with no recorded amount has no cost per wear, not a zero one.
type CostPerWear struct {
	Currency         string `json:"currency"`
	AmountMinor      int64  `json:"amount_minor"`
	CurrencyExponent int    `json:"currency_exponent"`
	WearEvents       int64  `json:"wear_events"`
}
type GarmentUsage struct {
	GarmentID   string       `json:"garment_id"`
	Name        string       `json:"name"`
	Category    string       `json:"category"`
	Archived    bool         `json:"archived"`
	WearEvents  int64        `json:"wear_events"`
	WearDays    int64        `json:"wear_days"`
	CostPerWear *CostPerWear `json:"cost_per_wear,omitempty"`
}

// UnwornGarment reports confirmed wear history on or before the review end date, so a garment not
// worn in the range is visibly different from one that has never been worn at all.
type UnwornGarment struct {
	GarmentID  string  `json:"garment_id"`
	Name       string  `json:"name"`
	Category   string  `json:"category"`
	Archived   bool    `json:"archived"`
	CreatedOn  string  `json:"created_on"`
	WearEvents int64   `json:"wear_events"`
	LastWornOn *string `json:"last_worn_on"`
}
type ColourUsage struct {
	Colour       string `json:"colour"`
	Garments     int64  `json:"garments"`
	WornGarments int64  `json:"worn_garments"`
	WearEvents   int64  `json:"wear_events"`
}
type UsageTrend struct {
	WeekStart  string `json:"week_start"`
	WearEvents int64  `json:"wear_events"`
	WearDays   int64  `json:"wear_days"`
}
type RatingBucket struct {
	Rating   int64 `json:"rating"`
	Feedback int64 `json:"feedback"`
}

// FeedbackSummary counts explicit feedback only. Views, plans and ratings never create wear events.
type FeedbackSummary struct {
	Records      int64          `json:"records"`
	Rated        int64          `json:"rated"`
	ComfortRated int64          `json:"comfort_rated"`
	StyleRated   int64          `json:"style_rated"`
	Comments     int64          `json:"comments"`
	Ratings      []RatingBucket `json:"ratings"`
	Comfort      []RatingBucket `json:"comfort"`
	Style        []RatingBucket `json:"style"`
}

// SelectionSummary keeps saved daily choices and plans apart from actual wears.
type SelectionSummary struct {
	SelectedDays   int64 `json:"selected_days"`
	ConfirmedDays  int64 `json:"confirmed_days"`
	ClearedDays    int64 `json:"cleared_days"`
	PlannedOutfits int64 `json:"planned_outfits"`
}

type Analysis struct {
	From           string          `json:"from,omitempty"`
	To             string          `json:"to,omitempty"`
	OutfitEvents   int64           `json:"outfit_events"`
	WearDays       int64           `json:"wear_days"`
	Garments       int64           `json:"garments"`
	UnwornGarments int64           `json:"unworn_garments"`
	Categories     []CategoryUsage `json:"categories"`

	MostWorn    []GarmentUsage `json:"most_worn"`
	LeastWorn   []GarmentUsage `json:"least_worn"`
	RankedLimit int64          `json:"ranked_limit"`

	NotWornInRange      []UnwornGarment `json:"not_worn_in_range"`
	NotWornInRangeTotal int64           `json:"not_worn_in_range_total"`
	NeverWorn           []UnwornGarment `json:"never_worn"`
	NeverWornTotal      int64           `json:"never_worn_total"`
	UnwornLimit         int64           `json:"unworn_limit"`

	Colours          []ColourUsage `json:"colours"`
	ColoursTruncated bool          `json:"colours_truncated"`

	Weeks          []UsageTrend `json:"weeks"`
	WeeksTruncated bool         `json:"weeks_truncated"`

	Feedback   FeedbackSummary  `json:"feedback"`
	Selections SelectionSummary `json:"selections"`
}

// usageCTEs is the shared wear aggregation: `ranged` counts confirmed wears inside the requested
// dates, `lifetime` counts every confirmed wear on or before the end date. Only outfits whose
// current state is worn are counted, so voiding or correcting a record changes these numbers.
const usageCTEs = `WITH lifetime AS (
	SELECT i.garment_id, count(*) events, max(o.day)::text last_day
	FROM retro.outfit_items i JOIN retro.outfits o ON o.id=i.outfit_id
	WHERE o.state='worn' AND ($2='' OR o.day<=NULLIF($2,'')::date)
	GROUP BY i.garment_id
), ranged AS (
	SELECT i.garment_id, count(*) events, count(DISTINCT o.day) days
	FROM retro.outfit_items i JOIN retro.outfits o ON o.id=i.outfit_id
	WHERE o.state='worn' AND ($1='' OR o.day>=NULLIF($1,'')::date) AND ($2='' OR o.day<=NULLIF($2,'')::date)
	GROUP BY i.garment_id
), ranked AS (
	SELECT g.id, g.name, g.category, g.archived_at IS NOT NULL archived, g.created_at, g.attributes,
		coalesce(r.events,0)::bigint events, coalesce(r.days,0)::bigint days,
		coalesce(l.events,0)::bigint lifetime_events, l.last_day
	FROM retro.garments g
	LEFT JOIN ranged r ON r.garment_id=g.id
	LEFT JOIN lifetime l ON l.garment_id=g.id
)
`

func analyze(ctx context.Context, u *unit, in AnalyzeInput) (Analysis, error) {
	result := Analysis{From: in.From, To: in.To, Categories: []CategoryUsage{}, MostWorn: []GarmentUsage{}, LeastWorn: []GarmentUsage{},
		NotWornInRange: []UnwornGarment{}, NeverWorn: []UnwornGarment{}, Colours: []ColourUsage{}, Weeks: []UsageTrend{},
		Feedback:    FeedbackSummary{Ratings: []RatingBucket{}, Comfort: []RatingBucket{}, Style: []RatingBucket{}},
		RankedLimit: rankedLimit, UnwornLimit: unwornLimit}
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
	if e = categoryUsage(ctx, u, in, &result); e != nil {
		return result, e
	}
	if e = rankedUsage(ctx, u, in, &result); e != nil {
		return result, e
	}
	if e = unwornUsage(ctx, u, in, &result); e != nil {
		return result, e
	}
	if e = colourUsage(ctx, u, in, &result); e != nil {
		return result, e
	}
	if e = weekUsage(ctx, u, in, &result); e != nil {
		return result, e
	}
	if e = feedbackUsage(ctx, u, in, &result); e != nil {
		return result, e
	}
	return result, selectionUsage(ctx, u, in, &result)
}

func categoryUsage(ctx context.Context, u *unit, in AnalyzeInput, result *Analysis) error {
	rows, e := u.tx.Query(ctx, `WITH usage AS (SELECT i.garment_id,count(*) events FROM retro.outfit_items i JOIN retro.outfits o ON o.id=i.outfit_id WHERE o.state='worn' AND ($1='' OR o.day>=NULLIF($1,'')::date) AND ($2='' OR o.day<=NULLIF($2,'')::date) GROUP BY i.garment_id)
 SELECT g.category,count(*),count(usage.garment_id),coalesce(sum(usage.events),0)::bigint FROM retro.garments g LEFT JOIN usage ON g.id=usage.garment_id GROUP BY g.category ORDER BY g.category`, in.From, in.To)
	if e != nil {
		return e
	}
	defer rows.Close()
	for rows.Next() {
		var c CategoryUsage
		if e = rows.Scan(&c.Category, &c.Garments, &c.WornGarments, &c.WearEvents); e != nil {
			return e
		}
		result.Categories = append(result.Categories, c)
		result.Garments += c.Garments
		result.UnwornGarments += c.Garments - c.WornGarments
	}
	return rows.Err()
}

// rankedUsage returns the most and least worn garments in the range. Ranks are computed for every
// garment and only the two bounded windows are returned, so the caps never hide a worn garment
// behind an unworn one.
func rankedUsage(ctx context.Context, u *unit, in AnalyzeInput, result *Analysis) error {
	rows, e := u.tx.Query(ctx, usageCTEs+`SELECT garment_id,name,category,archived,events,days,lifetime_events,purchase,recent_rank,quiet_rank FROM (
	SELECT id::text garment_id, name, category, archived, events, days, lifetime_events, attributes->'purchase' purchase,
		row_number() OVER (ORDER BY events DESC, id DESC) recent_rank,
		row_number() OVER (ORDER BY events ASC, id) quiet_rank
	FROM ranked) t
 WHERE recent_rank <= $3 OR quiet_rank <= $3`, in.From, in.To, rankedLimit+1)
	if e != nil {
		return e
	}
	defer rows.Close()
	for rows.Next() {
		var g GarmentUsage
		var purchase []byte
		var lifetime, recentRank, quietRank int64
		if e = rows.Scan(&g.GarmentID, &g.Name, &g.Category, &g.Archived, &g.WearEvents, &g.WearDays, &lifetime, &purchase, &recentRank, &quietRank); e != nil {
			return e
		}
		if g.WearEvents < 1 {
			continue // an unworn garment belongs to the never-worn lists, not a ranked list
		}
		g.CostPerWear = costPerWear(purchase, lifetime)
		if recentRank <= rankedLimit {
			result.MostWorn = append(result.MostWorn, g)
		}
		if quietRank <= rankedLimit {
			result.LeastWorn = append(result.LeastWorn, g)
		}
	}
	return rows.Err()
}

// costPerWear divides one garment's recorded amount by its confirmed wear events, rounded to the
// nearest minor unit. It is absent when either side is unknown, and it is never a cross-currency total.
func costPerWear(purchase []byte, wearEvents int64) *CostPerWear {
	var record PurchaseRecord
	if wearEvents < 1 || len(purchase) == 0 || json.Unmarshal(purchase, &record) != nil || record.AmountMinor == nil || record.Currency == "" {
		return nil
	}
	return &CostPerWear{Currency: record.Currency, AmountMinor: (*record.AmountMinor + wearEvents/2) / wearEvents,
		CurrencyExponent: currencyExponent(record.Currency), WearEvents: wearEvents}
}

// unwornUsage lists garments with no confirmed wear in the range, oldest first, and marks the ones
// that have never been worn on or before the end date at all.
func unwornUsage(ctx context.Context, u *unit, in AnalyzeInput, result *Analysis) error {
	if e := u.tx.QueryRow(ctx, usageCTEs+`SELECT count(*) FILTER (WHERE events=0), count(*) FILTER (WHERE events=0 AND lifetime_events=0) FROM ranked`, in.From, in.To).
		Scan(&result.NotWornInRangeTotal, &result.NeverWornTotal); e != nil {
		return e
	}
	rows, e := u.tx.Query(ctx, usageCTEs+`SELECT id::text,name,category,archived,created_at::date::text,lifetime_events,last_day FROM ranked WHERE events=0 ORDER BY created_at,name,id LIMIT $3`, in.From, in.To, unwornLimit+1)
	if e != nil {
		return e
	}
	defer rows.Close()
	for rows.Next() {
		var g UnwornGarment
		if e = rows.Scan(&g.GarmentID, &g.Name, &g.Category, &g.Archived, &g.CreatedOn, &g.WearEvents, &g.LastWornOn); e != nil {
			return e
		}
		if len(result.NotWornInRange) < unwornLimit {
			result.NotWornInRange = append(result.NotWornInRange, g)
		}
		if g.LastWornOn == nil && len(result.NeverWorn) < unwornLimit {
			result.NeverWorn = append(result.NeverWorn, g)
		}
	}
	return rows.Err()
}

// colourUsage distributes recorded colour tags over the inventory and its confirmed wear. A garment
// with several colours contributes to each, so the entries do not sum to the garment count.
func colourUsage(ctx context.Context, u *unit, in AnalyzeInput, result *Analysis) error {
	rows, e := u.tx.Query(ctx, usageCTEs+`SELECT lower(c.value) colour, count(*), count(*) FILTER (WHERE t.events>0), coalesce(sum(t.events),0)::bigint
 FROM ranked t CROSS JOIN LATERAL jsonb_array_elements_text(coalesce(t.attributes->'colours','[]'::jsonb)) c
 GROUP BY colour ORDER BY count(*) DESC, colour LIMIT $3`, in.From, in.To, colourLimit+1)
	if e != nil {
		return e
	}
	defer rows.Close()
	for rows.Next() {
		var c ColourUsage
		if e = rows.Scan(&c.Colour, &c.Garments, &c.WornGarments, &c.WearEvents); e != nil {
			return e
		}
		if len(result.Colours) >= colourLimit {
			result.ColoursTruncated = true
			continue
		}
		result.Colours = append(result.Colours, c)
	}
	return rows.Err()
}

// weekUsage buckets confirmed wears by calendar week (Monday start). An empty range has no weeks.
func weekUsage(ctx context.Context, u *unit, in AnalyzeInput, result *Analysis) error {
	from := in.From
	if from == "" {
		var earliest *string
		if e := u.tx.QueryRow(ctx, `SELECT min(day)::text FROM retro.outfits WHERE state='worn' AND ($1='' OR day<=NULLIF($1,'')::date)`, in.To).Scan(&earliest); e != nil {
			return e
		}
		if earliest == nil {
			return nil
		}
		from = *earliest
	}
	to := in.To
	if to == "" {
		to = time.Now().UTC().Format("2006-01-02")
	}
	rows, e := u.tx.Query(ctx, `SELECT w.week::date::text, count(o.id)::bigint, count(DISTINCT o.day)::bigint
 FROM generate_series(date_trunc('week',$1::date), date_trunc('week',$2::date), interval '1 week') w(week)
 LEFT JOIN retro.outfits o ON o.state='worn' AND o.day>=greatest(w.week::date,$1::date) AND o.day<=least((w.week+interval '1 week' - interval '1 day')::date,$2::date)
 GROUP BY w.week ORDER BY w.week DESC LIMIT $3`, from, to, weekLimit+1)
	if e != nil {
		return e
	}
	defer rows.Close()
	for rows.Next() {
		var t UsageTrend
		if e = rows.Scan(&t.WeekStart, &t.WearEvents, &t.WearDays); e != nil {
			return e
		}
		if len(result.Weeks) >= weekLimit {
			result.WeeksTruncated = true
			continue
		}
		result.Weeks = append([]UsageTrend{t}, result.Weeks...)
	}
	return rows.Err()
}

// feedbackUsage summarizes explicit feedback recorded for worn outfits in the range.
func feedbackUsage(ctx context.Context, u *unit, in AnalyzeInput, result *Analysis) error {
	if e := u.tx.QueryRow(ctx, `SELECT count(*),count(f.attributes->>'rating'),count(f.attributes->>'comfort_rating'),count(f.attributes->>'style_rating'),
 count(*) FILTER (WHERE coalesce(f.attributes->>'comment','')<>'')
 FROM retro.outfit_feedback f JOIN retro.outfits o ON o.id=f.outfit_id
 WHERE o.state='worn' AND ($1='' OR o.day>=NULLIF($1,'')::date) AND ($2='' OR o.day<=NULLIF($2,'')::date)`, in.From, in.To).
		Scan(&result.Feedback.Records, &result.Feedback.Rated, &result.Feedback.ComfortRated, &result.Feedback.StyleRated, &result.Feedback.Comments); e != nil {
		return e
	}
	rows, e := u.tx.Query(ctx, `SELECT v.kind,(v.value)::bigint,count(*)::bigint FROM retro.outfit_feedback f JOIN retro.outfits o ON o.id=f.outfit_id
 CROSS JOIN LATERAL (VALUES ('rating',(f.attributes->>'rating')::int),('comfort',(f.attributes->>'comfort_rating')::int),('style',(f.attributes->>'style_rating')::int)) v(kind,value)
 WHERE o.state='worn' AND v.value IS NOT NULL AND ($1='' OR o.day>=NULLIF($1,'')::date) AND ($2='' OR o.day<=NULLIF($2,'')::date)
 GROUP BY v.kind,v.value ORDER BY v.kind,v.value`, in.From, in.To)
	if e != nil {
		return e
	}
	defer rows.Close()
	for rows.Next() {
		var kind string
		var bucket RatingBucket
		if e = rows.Scan(&kind, &bucket.Rating, &bucket.Feedback); e != nil {
			return e
		}
		switch kind {
		case "rating":
			result.Feedback.Ratings = append(result.Feedback.Ratings, bucket)
		case "comfort":
			result.Feedback.Comfort = append(result.Feedback.Comfort, bucket)
		case "style":
			result.Feedback.Style = append(result.Feedback.Style, bucket)
		}
	}
	return rows.Err()
}

// selectionUsage keeps saved daily choices and plans separate from confirmed wears.
func selectionUsage(ctx context.Context, u *unit, in AnalyzeInput, result *Analysis) error {
	if e := u.tx.QueryRow(ctx, `SELECT count(*) FILTER (WHERE s.outfit_id IS NOT NULL),count(*) FILTER (WHERE o.state='worn'),count(*) FILTER (WHERE s.outfit_id IS NULL)
 FROM retro.day_selections s LEFT JOIN retro.outfits o ON o.id=s.outfit_id
 WHERE ($1='' OR s.day>=NULLIF($1,'')::date) AND ($2='' OR s.day<=NULLIF($2,'')::date)`, in.From, in.To).
		Scan(&result.Selections.SelectedDays, &result.Selections.ConfirmedDays, &result.Selections.ClearedDays); e != nil {
		return e
	}
	return u.tx.QueryRow(ctx, `SELECT count(*) FROM retro.outfits WHERE state='planned' AND ($1='' OR day>=NULLIF($1,'')::date) AND ($2='' OR day<=NULLIF($2,'')::date)`, in.From, in.To).Scan(&result.Selections.PlannedOutfits)
}
