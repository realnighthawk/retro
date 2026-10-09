package engine

import (
	"context"
	"encoding/json"
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
	if e = patchFields(&data, in.Patch, "name", "category", "availability", "subtype", "colours", "warmth", "seasons", "formality", "material", "brand", "notes", "favourite", "media_ids", "care", "laundry_reminder"); e != nil {
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
func listGarments(ctx context.Context, u *unit, in GarmentListInput) (Page[Garment], error) {
	result := Page[Garment]{Items: []Garment{}}
	filters := in
	filters.ListInput = ListInput{}
	limit, after, e := page(in.ListInput, filters)
	if e != nil {
		return result, e
	}
	if len(in.Search) > 100 {
		return result, invalid("search exceeds 100 bytes")
	}
	if in.Category != "" && !oneOf(in.Category, "top", "bottom", "one_piece", "outerwear", "footwear", "accessory", "other") {
		return result, invalid("unsupported category")
	}
	if in.Availability != "" && !oneOf(in.Availability, "ready", "needs_wash", "washing", "unavailable") {
		return result, invalid("unsupported availability")
	}
	rows, e := u.tx.Query(ctx, `SELECT id::text FROM retro.garments WHERE ($1 OR archived_at IS NULL) AND ($2='' OR category=$2) AND ($3='' OR availability=$3) AND ($4='' OR strpos(lower(name),lower($4))>0) AND ($5='' OR id>NULLIF($5,'')::uuid) ORDER BY id LIMIT $6`, in.IncludeArchived, in.Category, in.Availability, in.Search, after, limit+1)
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
	if len(ids) > limit {
		ids = ids[:limit]
		result.NextCursor = cursor(filters, ids[len(ids)-1])
	}
	for _, v := range ids {
		g, e := u.getGarment(ctx, v)
		if e != nil {
			return result, e
		}
		result.Items = append(result.Items, g)
	}
	return result, nil
}
