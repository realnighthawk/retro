package engine

import (
	"context"
	"encoding/json"
	"time"
)

func (u *unit) getOutfit(ctx context.Context, value string) (Outfit, error) {
	var o Outfit
	key, e := id(value)
	if e != nil {
		return o, e
	}
	e = u.tx.QueryRow(ctx, `SELECT id::text,version,day::text,time_zone,state,coalesce(previous_state,''),label,occasion,notes,source,confirmed_at,created_at,updated_at FROM retro.outfits WHERE id=$1`, key).Scan(&o.ID, &o.Version, &o.Day, &o.TimeZone, &o.State, &o.PreviousState, &o.Label, &o.Occasion, &o.Notes, &o.Source, &o.ConfirmedAt, &o.CreatedAt, &o.UpdatedAt)
	if e != nil {
		return o, e
	}
	o.Items = []OutfitItem{}
	rows, e := u.tx.Query(ctx, `SELECT garment_id::text,role,snapshot FROM retro.outfit_items WHERE outfit_id=$1 ORDER BY position`, key)
	if e != nil {
		return o, e
	}
	for rows.Next() {
		var item OutfitItem
		var snap []byte
		if e = rows.Scan(&item.GarmentID, &item.Role, &snap); e != nil {
			rows.Close()
			return o, e
		}
		if snap != nil {
			item.Snapshot = &Garment{}
			if e = json.Unmarshal(snap, item.Snapshot); e != nil {
				rows.Close()
				return o, e
			}
		}
		o.Items = append(o.Items, item)
	}
	e = rows.Err()
	rows.Close()
	if e != nil {
		return o, e
	}
	if o.State == "planned" {
		for i := range o.Items {
			g, e := u.getGarment(ctx, o.Items[i].GarmentID)
			if e != nil {
				return o, e
			}
			o.Items[i].Snapshot = &g
		}
	}
	return o, nil
}
func selections(o Outfit) []Selection {
	items := make([]Selection, 0, len(o.Items))
	for _, item := range o.Items {
		items = append(items, item.Selection)
	}
	return items
}
func (u *unit) saveItems(ctx context.Context, o Outfit, items []Selection) error {
	if e := validateSelections(items); e != nil {
		return e
	}
	if _, e := u.tx.Exec(ctx, `DELETE FROM retro.outfit_items WHERE outfit_id=$1`, o.ID); e != nil {
		return e
	}
	if _, e := u.tx.Exec(ctx, `DELETE FROM retro.outfit_media WHERE outfit_id=$1`, o.ID); e != nil {
		return e
	}
	for pos, item := range items {
		g, e := u.getGarment(ctx, item.GarmentID)
		if e != nil {
			return e
		}
		if o.State == "planned" && g.ArchivedAt != nil {
			return conflict("planned outfits require active garments")
		}
		var snap []byte
		if o.State == "worn" {
			// Historical snapshots contain inventory facts, not usage totals that change with this write.
			g.WearStats = WearStats{}
			snap, e = json.Marshal(g)
			if e != nil {
				return e
			}
			for _, mid := range g.MediaIDs {
				if _, e = u.tx.Exec(ctx, `INSERT INTO retro.outfit_media(outfit_id,media_id) VALUES($1,$2) ON CONFLICT DO NOTHING`, o.ID, mid); e != nil {
					return e
				}
			}
		}
		if _, e = u.tx.Exec(ctx, `INSERT INTO retro.outfit_items(outfit_id,garment_id,position,role,snapshot) VALUES($1,$2,$3,$4,$5)`, o.ID, g.ID, pos, item.Role, snap); e != nil {
			return e
		}
	}
	return nil
}
func createOutfit(ctx context.Context, u *unit, in CreateOutfitInput) (OutfitResult, error) {
	var result OutfitResult
	key, e := createID(in.ID)
	if e != nil {
		return result, e
	}
	if e = validateOutfit(&in.OutfitData, time.Now()); e != nil {
		return result, e
	}
	if e = validateSelections(in.Items); e != nil {
		return result, e
	}
	_, e = u.tx.Exec(ctx, `INSERT INTO retro.outfits(id,day,time_zone,state,label,occasion,notes,source,confirmed_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,CASE WHEN $4='worn' THEN now() ELSE NULL END)`, key, in.Day, in.TimeZone, in.State, in.Label, in.Occasion, in.Notes, in.Source)
	if e != nil {
		return result, e
	}
	o := Outfit{ID: key, OutfitData: in.OutfitData}
	if e = u.saveItems(ctx, o, in.Items); e != nil {
		return result, e
	}
	o, e = u.getOutfit(ctx, key)
	if e != nil {
		return result, e
	}
	result.Outfit = o
	return result, u.audit(ctx, "outfit", key, nil, o)
}
func updateOutfit(ctx context.Context, u *unit, in PatchInput) (OutfitResult, error) {
	var result OutfitResult
	before, e := u.getOutfit(ctx, in.ID)
	if e != nil {
		return result, e
	}
	if e = version(in.ExpectedVersion, before.Version); e != nil {
		return result, e
	}
	if before.State == "void" {
		return result, conflict("restore this outfit before editing")
	}
	items := selections(before)
	data := before.OutfitData
	header := map[string]json.RawMessage{}
	for k, v := range in.Patch {
		if k == "items" {
			if e = json.Unmarshal(v, &items); e != nil {
				return result, invalid("items must be a selection array")
			}
		} else {
			header[k] = v
		}
	}
	if len(in.Patch) == 0 {
		return result, invalid("patch cannot be empty")
	}
	if len(header) > 0 {
		if e = patchFields(&data, header, "day", "time_zone", "label", "occasion", "notes"); e != nil {
			return result, e
		}
	}
	if e = validateOutfit(&data, time.Now()); e != nil {
		return result, e
	}
	_, e = u.tx.Exec(ctx, `UPDATE retro.outfits SET day=$2,time_zone=$3,label=$4,occasion=$5,notes=$6,version=version+1,updated_at=now() WHERE id=$1`, before.ID, data.Day, data.TimeZone, data.Label, data.Occasion, data.Notes)
	if e != nil {
		return result, e
	}
	o := before
	o.OutfitData = data
	if _, changed := in.Patch["items"]; changed {
		if e = u.saveItems(ctx, o, items); e != nil {
			return result, e
		}
	}
	o, e = u.getOutfit(ctx, before.ID)
	if e != nil {
		return result, e
	}
	result.Outfit = o
	return result, u.audit(ctx, "outfit", o.ID, before, o)
}
func confirmOutfit(ctx context.Context, u *unit, in ConfirmInput) (OutfitResult, error) {
	var result OutfitResult
	before, e := u.getOutfit(ctx, in.ID)
	if e != nil {
		return result, e
	}
	if e = version(in.ExpectedVersion, before.Version); e != nil {
		return result, e
	}
	if before.State != "planned" {
		return result, conflict("only a planned outfit can be confirmed")
	}
	o := before
	o.State = "worn"
	if e = validateOutfit(&o.OutfitData, time.Now()); e != nil {
		return result, e
	}
	items := in.Items
	if items == nil {
		items = selections(before)
	}
	for _, item := range items {
		g, e := u.getGarment(ctx, item.GarmentID)
		if e != nil {
			return result, e
		}
		if g.ArchivedAt != nil {
			return result, conflict("a planned garment was archived; choose another piece")
		}
	}
	_, e = u.tx.Exec(ctx, `UPDATE retro.outfits SET state='worn',confirmed_at=now(),version=version+1,updated_at=now() WHERE id=$1`, o.ID)
	if e != nil {
		return result, e
	}
	if e = u.saveItems(ctx, o, items); e != nil {
		return result, e
	}
	o, e = u.getOutfit(ctx, o.ID)
	if e != nil {
		return result, e
	}
	result.Outfit = o
	return result, u.audit(ctx, "outfit", o.ID, before, o)
}
func lifecycleOutfit(ctx context.Context, u *unit, in EditInput, restore bool) (OutfitResult, error) {
	var result OutfitResult
	before, e := u.getOutfit(ctx, in.ID)
	if e != nil {
		return result, e
	}
	if e = version(in.ExpectedVersion, before.Version); e != nil {
		return result, e
	}
	if restore != (before.State == "void") {
		return result, conflict("outfit is already in that state")
	}
	if restore {
		data := before.OutfitData
		data.State = before.PreviousState
		if e = validateOutfit(&data, time.Now()); e != nil {
			return result, e
		}
		if data.State == "planned" {
			for _, item := range before.Items {
				g, e := u.getGarment(ctx, item.GarmentID)
				if e != nil {
					return result, e
				}
				if g.ArchivedAt != nil {
					return result, conflict("planned outfit contains an archived garment")
				}
			}
		}
	}
	_, e = u.tx.Exec(ctx, `UPDATE retro.outfits SET state=CASE WHEN $2 THEN previous_state ELSE 'void' END,previous_state=CASE WHEN $2 THEN NULL ELSE state END,version=version+1,updated_at=now() WHERE id=$1`, before.ID, restore)
	if e != nil {
		return result, e
	}
	o, e := u.getOutfit(ctx, before.ID)
	if e != nil {
		return result, e
	}
	result.Outfit = o
	return result, u.audit(ctx, "outfit", o.ID, before, o)
}
func listOutfits(ctx context.Context, u *unit, in OutfitListInput) (Page[Outfit], error) {
	result := Page[Outfit]{Items: []Outfit{}}
	filters := in
	filters.ListInput = ListInput{}
	limit, after, _, e := page(in.ListInput, filters)
	if e != nil {
		return result, e
	}
	if in.From != "" {
		if e = date(in.From); e != nil {
			return result, e
		}
	}
	if in.To != "" {
		if e = date(in.To); e != nil {
			return result, e
		}
	}
	if in.From != "" && in.To != "" && in.From > in.To {
		return result, invalid("from must not exceed to")
	}
	if in.State != "" && !oneOf(in.State, "planned", "worn", "void", "all") {
		return result, invalid("unsupported state")
	}
	if in.GarmentID != "" {
		if _, e = id(in.GarmentID); e != nil {
			return result, e
		}
	}
	rows, e := u.tx.Query(ctx, `SELECT id::text FROM retro.outfits o WHERE ($1='' OR day>=NULLIF($1,'')::date) AND ($2='' OR day<=NULLIF($2,'')::date) AND (($3='' AND state<>'void') OR $3='all' OR state=$3) AND ($4='' OR EXISTS(SELECT 1 FROM retro.outfit_items i WHERE i.outfit_id=o.id AND garment_id=NULLIF($4,'')::uuid)) AND ($5='' OR id>NULLIF($5,'')::uuid) ORDER BY id LIMIT $6`, in.From, in.To, in.State, in.GarmentID, after, limit+1)
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
		result.NextCursor = cursor(filters, ids[len(ids)-1], "")
	}
	for _, v := range ids {
		o, e := u.getOutfit(ctx, v)
		if e != nil {
			return result, e
		}
		result.Items = append(result.Items, o)
	}
	return result, nil
}
func dayGet(ctx context.Context, u *unit, in DayInput) (DayResult, error) {
	result := DayResult{Day: in.Day, Outfits: []Outfit{}}
	if e := date(in.Day); e != nil {
		return result, e
	}
	rows, e := u.tx.Query(ctx, `SELECT id::text FROM retro.outfits WHERE day=$1 AND ($2 OR state<>'void') ORDER BY created_at,id LIMIT 201`, in.Day, in.IncludeVoid)
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
	if len(ids) > 200 {
		return result, invalid("day has more than 200 outfits; use outfits_list")
	}
	for _, v := range ids {
		o, e := u.getOutfit(ctx, v)
		if e != nil {
			return result, e
		}
		result.Outfits = append(result.Outfits, o)
	}
	result.Selection, e = u.getDaySelection(ctx, in.Day)
	return result, e
}
