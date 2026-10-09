package engine

import (
	"context"
	"strings"
	"time"
)

type PairingData struct {
	Name  string      `json:"name"`
	Notes string      `json:"notes,omitempty"`
	Items []Selection `json:"items"`
}
type Pairing struct {
	ID         string       `json:"id"`
	Version    int64        `json:"version"`
	Name       string       `json:"name"`
	Notes      string       `json:"notes,omitempty"`
	Items      []OutfitItem `json:"items"`
	ArchivedAt *time.Time   `json:"archived_at"`
	CreatedAt  time.Time    `json:"created_at"`
	UpdatedAt  time.Time    `json:"updated_at"`
}
type CreatePairingInput struct {
	Meta
	ID string `json:"id,omitempty"`
	PairingData
}
type PairingListInput struct {
	ListInput
	GarmentID       string `json:"garment_id,omitempty"`
	Search          string `json:"search,omitempty"`
	IncludeArchived bool   `json:"include_archived,omitempty"`
}
type PairingResult struct {
	Pairing Pairing `json:"pairing"`
}

func validatePairing(p *PairingData) error {
	p.Name = strings.TrimSpace(p.Name)
	p.Notes = strings.TrimSpace(p.Notes)
	if len(p.Name) < 1 || len(p.Name) > 100 || len(p.Notes) > 4000 || len(p.Items) < 2 {
		return invalid("a pairing needs a 1-100 byte name, at least two pieces and notes of at most 4000 bytes")
	}
	return validateSelections(p.Items)
}
func (u *unit) getPairing(ctx context.Context, value string) (Pairing, error) {
	var p Pairing
	key, e := id(value)
	if e != nil {
		return p, e
	}
	e = u.tx.QueryRow(ctx, `SELECT id::text,version,name,notes,archived_at,created_at,updated_at FROM retro.pairings WHERE id=$1`, key).Scan(&p.ID, &p.Version, &p.Name, &p.Notes, &p.ArchivedAt, &p.CreatedAt, &p.UpdatedAt)
	if e != nil {
		return p, e
	}
	p.Items = []OutfitItem{}
	rows, e := u.tx.Query(ctx, `SELECT garment_id::text,role FROM retro.pairing_items WHERE pairing_id=$1 ORDER BY position`, key)
	if e != nil {
		return p, e
	}
	for rows.Next() {
		var item OutfitItem
		if e = rows.Scan(&item.GarmentID, &item.Role); e != nil {
			rows.Close()
			return p, e
		}
		p.Items = append(p.Items, item)
	}
	e = rows.Err()
	rows.Close()
	if e != nil {
		return p, e
	}
	for i := range p.Items {
		g, e := u.getGarment(ctx, p.Items[i].GarmentID)
		if e != nil {
			return p, e
		}
		p.Items[i].Snapshot = &g
	}
	return p, nil
}
func (u *unit) savePairingItems(ctx context.Context, key string, items []Selection) error {
	if _, e := u.tx.Exec(ctx, `DELETE FROM retro.pairing_items WHERE pairing_id=$1`, key); e != nil {
		return e
	}
	for position, item := range items {
		g, e := u.getGarment(ctx, item.GarmentID)
		if e != nil {
			return e
		}
		if g.ArchivedAt != nil {
			return conflict("new pairing selections require active garments; replace archived pieces")
		}
		if _, e = u.tx.Exec(ctx, `INSERT INTO retro.pairing_items(pairing_id,garment_id,position,role) VALUES($1,$2,$3,$4)`, key, g.ID, position, item.Role); e != nil {
			return e
		}
	}
	return nil
}
func createPairing(ctx context.Context, u *unit, in CreatePairingInput) (PairingResult, error) {
	var result PairingResult
	key, e := createID(in.ID)
	if e != nil {
		return result, e
	}
	if e = validatePairing(&in.PairingData); e != nil {
		return result, e
	}
	if _, e = u.tx.Exec(ctx, `INSERT INTO retro.pairings(id,name,notes) VALUES($1,$2,$3)`, key, in.Name, in.Notes); e != nil {
		return result, e
	}
	if e = u.savePairingItems(ctx, key, in.Items); e != nil {
		return result, e
	}
	result.Pairing, e = u.getPairing(ctx, key)
	if e != nil {
		return result, e
	}
	return result, u.audit(ctx, "pairing", key, nil, result.Pairing)
}
func updatePairing(ctx context.Context, u *unit, in PatchInput) (PairingResult, error) {
	var result PairingResult
	before, e := u.getPairing(ctx, in.ID)
	if e != nil {
		return result, e
	}
	if e = version(in.ExpectedVersion, before.Version); e != nil {
		return result, e
	}
	if before.ArchivedAt != nil {
		return result, conflict("restore the pairing before editing")
	}
	data := PairingData{Name: before.Name, Notes: before.Notes, Items: []Selection{}}
	for _, item := range before.Items {
		data.Items = append(data.Items, item.Selection)
	}
	if e = patchFields(&data, in.Patch, "name", "notes", "items"); e != nil {
		return result, e
	}
	if e = validatePairing(&data); e != nil {
		return result, e
	}
	if _, e = u.tx.Exec(ctx, `UPDATE retro.pairings SET name=$2,notes=$3,version=version+1,updated_at=now() WHERE id=$1`, before.ID, data.Name, data.Notes); e != nil {
		return result, e
	}
	if _, changed := in.Patch["items"]; changed {
		if e = u.savePairingItems(ctx, before.ID, data.Items); e != nil {
			return result, e
		}
	}
	result.Pairing, e = u.getPairing(ctx, before.ID)
	if e != nil {
		return result, e
	}
	return result, u.audit(ctx, "pairing", before.ID, before, result.Pairing)
}
func lifecyclePairing(ctx context.Context, u *unit, in EditInput, restore bool) (PairingResult, error) {
	var result PairingResult
	before, e := u.getPairing(ctx, in.ID)
	if e != nil {
		return result, e
	}
	if e = version(in.ExpectedVersion, before.Version); e != nil {
		return result, e
	}
	if restore == (before.ArchivedAt == nil) {
		return result, conflict("pairing is already in that state")
	}
	_, e = u.tx.Exec(ctx, `UPDATE retro.pairings SET archived_at=CASE WHEN $2 THEN NULL ELSE now() END,version=version+1,updated_at=now() WHERE id=$1`, before.ID, restore)
	if e != nil {
		return result, e
	}
	result.Pairing, e = u.getPairing(ctx, before.ID)
	if e != nil {
		return result, e
	}
	return result, u.audit(ctx, "pairing", before.ID, before, result.Pairing)
}
func listPairings(ctx context.Context, u *unit, in PairingListInput) (Page[Pairing], error) {
	result := Page[Pairing]{Items: []Pairing{}}
	filters := in
	filters.ListInput = ListInput{}
	limit, after, e := page(in.ListInput, filters)
	if e != nil {
		return result, e
	}
	if len(in.Search) > 100 {
		return result, invalid("search exceeds 100 bytes")
	}
	if in.GarmentID != "" {
		if in.GarmentID, e = id(in.GarmentID); e != nil {
			return result, e
		}
	}
	rows, e := u.tx.Query(ctx, `SELECT p.id::text FROM retro.pairings p WHERE ($1 OR p.archived_at IS NULL)
	 AND ($2='' OR EXISTS(SELECT 1 FROM retro.pairing_items i WHERE i.pairing_id=p.id AND i.garment_id=NULLIF($2,'')::uuid))
	 AND ($3='' OR strpos(lower(p.name),lower($3))>0) AND ($4='' OR p.id>NULLIF($4,'')::uuid) ORDER BY p.id LIMIT $5`, in.IncludeArchived, in.GarmentID, in.Search, after, limit+1)
	if e != nil {
		return result, e
	}
	ids := []string{}
	for rows.Next() {
		var key string
		if e = rows.Scan(&key); e != nil {
			rows.Close()
			return result, e
		}
		ids = append(ids, key)
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
	for _, key := range ids {
		p, e := u.getPairing(ctx, key)
		if e != nil {
			return result, e
		}
		result.Items = append(result.Items, p)
	}
	return result, nil
}
