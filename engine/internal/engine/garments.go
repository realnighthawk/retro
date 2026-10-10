package engine

import (
	"context"
	"encoding/json"
	"fmt"
	"time"
)

const garmentJSON = `g.attributes || jsonb_build_object('id',g.id::text,'version',g.version,'name',g.name,'category',g.category,'availability',g.availability,'archived_at',g.archived_at,'created_at',g.created_at,'updated_at',g.updated_at)`

func (u *unit) getGarment(ctx context.Context, value string) (Garment, error) {
	var g Garment
	key, e := id(value)
	if e != nil {
		return g, e
	}
	var raw []byte
	e = u.tx.QueryRow(ctx, `SELECT `+garmentJSON+` FROM retro.garments g WHERE id=$1`, key).Scan(&raw)
	if e != nil {
		return g, e
	}
	if e = json.Unmarshal(raw, &g); e != nil {
		return g, e
	}
	e = u.tx.QueryRow(ctx, `SELECT count(DISTINCT o.day),count(*),max(o.day)::text FROM retro.outfit_items i JOIN retro.outfits o ON o.id=i.outfit_id WHERE i.garment_id=$1 AND o.state='worn'`, key).Scan(&g.WearDays, &g.WearEvents, &g.LastWornOn)
	return g, e
}
func (u *unit) attachMedia(ctx context.Context, g Garment) error {
	if _, e := u.tx.Exec(ctx, `DELETE FROM retro.garment_media WHERE garment_id=$1`, g.ID); e != nil {
		return e
	}
	for pos, mid := range g.MediaIDs {
		var state string
		if e := u.tx.QueryRow(ctx, `SELECT state FROM retro.media WHERE id=$1`, mid).Scan(&state); e != nil {
			return notFound()
		}
		if state != "ready" {
			return conflict("photo is not ready")
		}
		if _, e := u.tx.Exec(ctx, `INSERT INTO retro.garment_media(garment_id,media_id,position) VALUES($1,$2,$3)`, g.ID, mid, pos); e != nil {
			return e
		}
	}
	return nil
}
func createGarment(ctx context.Context, u *unit, in CreateGarmentInput) (GarmentResult, error) {
	var result GarmentResult
	key, e := createID(in.ID)
	if e != nil {
		return result, e
	}
	if e = validateGarment(&in.GarmentData); e != nil {
		return result, e
	}
	attrs, _ := json.Marshal(in.GarmentAttributes)
	_, e = u.tx.Exec(ctx, `INSERT INTO retro.garments(id,name,category,availability,attributes) VALUES($1,$2,$3,$4,$5)`, key, in.Name, in.Category, in.Availability, attrs)
	if e != nil {
		return result, e
	}
	g, e := u.getGarment(ctx, key)
	if e != nil {
		return result, e
	}
	if e = u.attachMedia(ctx, g); e != nil {
		return result, e
	}
	result.Garment = g
	return result, u.audit(ctx, "garment", key, nil, g)
}
func updateGarment(ctx context.Context, u *unit, in PatchInput) (GarmentResult, error) {
	var result GarmentResult
	before, e := u.getGarment(ctx, in.ID)
	if e != nil {
		return result, e
	}
	if e = version(in.ExpectedVersion, before.Version); e != nil {
		return result, e
	}
	if before.ArchivedAt != nil {
		return result, conflict("restore this garment before editing")
	}
	if e = u.ensureLaundryUnreserved(ctx, before.ID); e != nil {
		return result, e
	}
	data := before.GarmentData
	if e = patchFields(&data, in.Patch, "name", "category", "availability", "subtype", "colours", "warmth", "seasons", "formality", "material", "brand", "pattern", "style", "fit", "notes", "favourite", "media_ids", "purchase", "care", "laundry_reminder"); e != nil {
		return result, e
	}
	if e = validateGarment(&data); e != nil {
		return result, e
	}
	attrs, _ := json.Marshal(data.GarmentAttributes)
	_, e = u.tx.Exec(ctx, `UPDATE retro.garments SET name=$2,category=$3,availability=$4,attributes=$5,version=version+1,updated_at=now() WHERE id=$1`, before.ID, data.Name, data.Category, data.Availability, attrs)
	if e != nil {
		return result, e
	}
	g, e := u.getGarment(ctx, before.ID)
	if e != nil {
		return result, e
	}
	if e = u.attachMedia(ctx, g); e != nil {
		return result, e
	}
	result.Garment = g
	return result, u.audit(ctx, "garment", g.ID, before, g)
}
func lifecycleGarment(ctx context.Context, u *unit, in EditInput, restore bool) (GarmentResult, error) {
	var result GarmentResult
	before, e := u.getGarment(ctx, in.ID)
	if e != nil {
		return result, e
	}
	if e = version(in.ExpectedVersion, before.Version); e != nil {
		return result, e
	}
	if e = u.ensureLaundryUnreserved(ctx, before.ID); e != nil {
		return result, e
	}
	if restore == (before.ArchivedAt == nil) {
		return result, conflict("garment is already in that state")
	}
	_, e = u.tx.Exec(ctx, `UPDATE retro.garments SET archived_at=CASE WHEN $2 THEN NULL ELSE now() END,version=version+1,updated_at=now() WHERE id=$1`, before.ID, restore)
	if e != nil {
		return result, e
	}
	g, e := u.getGarment(ctx, before.ID)
	if e != nil {
		return result, e
	}
	result.Garment = g
	return result, u.audit(ctx, "garment", g.ID, before, g)
}

// garmentFilters is the predicate shared by the page query and the match count. Every predicate is
// optional; an absent filter is an empty string or a null pointer, never a wildcard value.
const garmentFilters = `($1 OR g.archived_at IS NULL)
	AND ($2='' OR g.category=$2)
	AND ($3='' OR g.availability=$3)
	AND ($4='' OR strpos(lower(g.name),lower($4))>0)
	AND ($5='' OR strpos(lower(coalesce(g.attributes->>'brand','')),lower($5))>0)
	AND ($6='' OR strpos(lower(coalesce(g.attributes->>'notes','')),lower($6))>0)
	AND ($7='' OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(coalesce(g.attributes->'colours','[]'::jsonb)) c WHERE lower(c)=lower($7)))
	AND ($8='' OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(coalesce(g.attributes->'seasons','[]'::jsonb)) s WHERE lower(s)=lower($8)))
	AND ($9::boolean IS NULL OR coalesce(g.attributes->>'favourite','false')::boolean=$9)
	AND ($10='' OR coalesce(g.attributes->'care'->>'wash_method','unknown')=$10)
	AND ($11::boolean IS NULL OR coalesce(g.attributes->'care'->>'confirmed','false')::boolean=$11)`

func garmentOrder(sort string) string {
	switch sort {
	case "name":
		return "lower(g.name), g.id"
	case "recent":
		return "g.updated_at DESC, g.id DESC"
	case "added":
		return "g.created_at DESC, g.id DESC"
	}
	return "g.id"
}

// garmentKey is the sort value a cursor continues from. It is compared with the stored column so
// paging never skips or repeats a tie: the ID breaks every tie in the same direction as the order.
func garmentKey(sort string, g Garment) string {
	switch sort {
	case "name":
		return g.Name
	case "recent":
		return g.UpdatedAt.UTC().Format(time.RFC3339Nano)
	case "added":
		return g.CreatedAt.UTC().Format(time.RFC3339Nano)
	}
	return ""
}

func listGarments(ctx context.Context, u *unit, in GarmentListInput) (GarmentPage, error) {
	result := GarmentPage{Items: []Garment{}}
	if in.Sort == "" {
		in.Sort = "id"
	}
	if !oneOf(in.Sort, "id", "name", "recent", "added") {
		return result, invalid("unsupported sort")
	}
	// The cursor scope covers the complete filter *and sort* request, so a changed query cannot
	// continue an older page. Defaulting the sort first keeps an omitted sort identical to "id".
	filters := in
	filters.ListInput = ListInput{}
	limit, after, key, e := page(in.ListInput, filters)
	if e != nil {
		return result, e
	}
	for _, text := range []string{in.Search, in.Brand, in.Notes, in.Colour, in.Season} {
		if len(text) > 100 {
			return result, invalid("search text exceeds 100 bytes")
		}
	}
	if in.Category != "" && !oneOf(in.Category, "top", "bottom", "one_piece", "outerwear", "footwear", "accessory", "other") {
		return result, invalid("unsupported category")
	}
	if in.Availability != "" && !oneOf(in.Availability, "ready", "needs_wash", "washing", "unavailable") {
		return result, invalid("unsupported availability")
	}
	if in.WashMethod != "" && !oneOf(in.WashMethod, "unknown", "machine", "hand", "dry_clean", "do_not_wash") {
		return result, invalid("unsupported wash method")
	}
	if after != "" && in.Sort != "id" && key == "" {
		return result, invalid("invalid cursor")
	}
	base := []any{in.IncludeArchived, in.Category, in.Availability, in.Search, in.Brand, in.Notes, in.Colour, in.Season, in.Favourite, in.WashMethod, in.CareConfirmed}
	if e = u.tx.QueryRow(ctx, `SELECT count(*) FROM retro.garments g WHERE `+garmentFilters, base...).Scan(&result.TotalMatches); e != nil {
		return result, e
	}
	args := append([]any{}, base...)
	query := `SELECT g.id::text FROM retro.garments g WHERE ` + garmentFilters
	switch {
	case after == "":
	case in.Sort == "recent", in.Sort == "added":
		// A timestamp cursor is compared as a timestamp so paging stays exact at sub-second precision.
		stamp, parseErr := time.Parse(time.RFC3339Nano, key)
		if parseErr != nil {
			return result, invalid("invalid cursor")
		}
		column := "updated_at"
		if in.Sort == "added" {
			column = "created_at"
		}
		args = append(args, stamp, after)
		query += fmt.Sprintf(` AND (g.%s, g.id) < ($%d, $%d::uuid)`, column, len(args)-1, len(args))
	case in.Sort == "name":
		args = append(args, key, after)
		query += fmt.Sprintf(` AND (lower(g.name), g.id) > (lower($%d), $%d::uuid)`, len(args)-1, len(args))
	default:
		args = append(args, after)
		query += fmt.Sprintf(` AND g.id > $%d::uuid`, len(args))
	}
	args = append(args, limit+1)
	query += fmt.Sprintf(` ORDER BY %s LIMIT $%d`, garmentOrder(in.Sort), len(args))
	rows, e := u.tx.Query(ctx, query, args...)
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
	hasMore := len(ids) > limit
	if hasMore {
		ids = ids[:limit]
	}
	for _, v := range ids {
		g, e := u.getGarment(ctx, v)
		if e != nil {
			return result, e
		}
		result.Items = append(result.Items, g)
	}
	if hasMore {
		last := result.Items[len(result.Items)-1]
		result.NextCursor = cursor(filters, last.ID, garmentKey(in.Sort, last))
	}
	return result, nil
}
