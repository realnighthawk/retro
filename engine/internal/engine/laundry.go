package engine

import (
	"context"
	"encoding/json"
	"sort"
	"strings"
	"time"
)

type LaundryProgram struct {
	WashMethod   string `json:"wash_method"`
	TemperatureC *int   `json:"temperature_c,omitempty"`
	Cycle        string `json:"cycle"`
	Drying       string `json:"drying"`
}
type LaundrySelection struct {
	GarmentID       string `json:"garment_id"`
	ExpectedVersion int64  `json:"expected_version"`
}
type LaundryCandidate struct {
	GarmentID string `json:"garment_id"`
	Version   int64  `json:"version"`
	Name      string `json:"name"`
}
type LaundryGroup struct {
	ID          string             `json:"id"`
	ColourGroup string             `json:"colour_group"`
	Items       []LaundryCandidate `json:"items"`
}
type LaundryBlocked struct {
	LaundryCandidate
	Reason string `json:"reason"`
}
type LaundryPreviewInput struct {
	Program LaundryProgram `json:"program"`
}
type LaundryPreview struct {
	Program        LaundryProgram   `json:"program"`
	GeneratedAt    time.Time        `json:"generated_at"`
	Coverage       string           `json:"coverage"`
	InventoryCount int              `json:"inventory_count"`
	Groups         []LaundryGroup   `json:"groups"`
	Blocked        []LaundryBlocked `json:"blocked"`
}
type LaundryData struct {
	Name     string             `json:"name"`
	Day      string             `json:"day"`
	TimeZone string             `json:"time_zone"`
	Program  LaundryProgram     `json:"program"`
	Items    []LaundrySelection `json:"items"`
}
type LaundryItem struct {
	LaundrySelection
	Snapshot Garment `json:"snapshot"`
}
type LaundryLoad struct {
	ID          string         `json:"id"`
	Version     int64          `json:"version"`
	Name        string         `json:"name"`
	Day         string         `json:"day"`
	TimeZone    string         `json:"time_zone"`
	State       string         `json:"state"`
	Program     LaundryProgram `json:"program"`
	Items       []LaundryItem  `json:"items"`
	StartedAt   *time.Time     `json:"started_at"`
	WashedAt    *time.Time     `json:"washed_at"`
	CompletedAt *time.Time     `json:"completed_at"`
	CancelledAt *time.Time     `json:"cancelled_at"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
}
type LaundryResult struct {
	Load LaundryLoad `json:"load"`
}
type CreateLaundryInput struct {
	Meta
	ID string `json:"id,omitempty"`
	LaundryData
}
type LaundryListInput struct {
	ListInput
	State     string `json:"state,omitempty"`
	GarmentID string `json:"garment_id,omitempty"`
}

func validateLaundryProgram(p LaundryProgram) error {
	if !oneOf(p.WashMethod, "machine", "hand", "dry_clean") {
		return invalid("choose machine wash, hand wash or dry cleaning")
	}
	if p.WashMethod == "dry_clean" {
		if p.TemperatureC != nil || p.Cycle != "unknown" || p.Drying != "professional" {
			return invalid("dry cleaning uses professional care without a wash temperature or cycle")
		}
		return nil
	}
	if p.TemperatureC == nil || *p.TemperatureC < 0 || *p.TemperatureC > 95 || !oneOf(p.Drying, "line", "flat", "tumble_low", "tumble_normal") {
		return invalid("choose an explicit wash temperature and drying method")
	}
	if p.WashMethod == "machine" && !oneOf(p.Cycle, "normal", "gentle", "delicate") || p.WashMethod == "hand" && p.Cycle != "unknown" {
		return invalid("machine wash needs a cycle; hand wash has no machine cycle")
	}
	return nil
}
func laundryRestriction(g Garment, p LaundryProgram) string {
	if g.ArchivedAt != nil || g.Availability != "needs_wash" {
		return "Only active garments marked needs wash can enter a load."
	}
	c := g.Care
	if c == nil || !c.Confirmed {
		return "Review and confirm the garment's care instructions first."
	}
	if c.WashMethod == "do_not_wash" {
		return "Do not wash: keep this garment out of laundry loads."
	}
	if c.WashMethod != p.WashMethod {
		return "Requires " + c.WashMethod + " care; keep it in a separate method list."
	}
	if !oneOf(c.ColourGroup, "white", "light", "dark", "separate") || c.Drying == "unknown" {
		return "Confirm colour separation and drying restrictions first."
	}
	if p.WashMethod != "dry_clean" {
		if c.MaxTempC == nil || p.TemperatureC == nil || *p.TemperatureC > *c.MaxTempC {
			return "The selected wash temperature exceeds or lacks a confirmed limit."
		}
		// shortcut: cycles match exactly; add gentler-cycle equivalence only after the owner's machine programmes are assessed.
		if p.WashMethod == "machine" && c.Cycle != p.Cycle {
			return "The selected cycle differs from the confirmed care cycle."
		}
	}
	if c.Drying != p.Drying && !(c.Drying == "do_not_tumble" && oneOf(p.Drying, "line", "flat")) {
		return "The selected drying method conflicts with confirmed care."
	}
	return ""
}
func laundryGroup(g Garment) string {
	if g.Care.ColourGroup == "separate" {
		return "separate:" + g.ID
	}
	return g.Care.ColourGroup
}
func previewLaundry(ctx context.Context, u *unit, in LaundryPreviewInput) (LaundryPreview, error) {
	result := LaundryPreview{Program: in.Program, GeneratedAt: time.Now().UTC(), Coverage: "active_needs_wash_only", Groups: []LaundryGroup{}, Blocked: []LaundryBlocked{}}
	if e := validateLaundryProgram(in.Program); e != nil {
		return result, e
	}
	rows, e := u.tx.Query(ctx, `SELECT `+garmentJSON+` FROM retro.garments g WHERE archived_at IS NULL AND availability='needs_wash' ORDER BY id LIMIT 2001`)
	if e != nil {
		return result, e
	}
	defer rows.Close()
	groups := map[string]*LaundryGroup{}
	for rows.Next() {
		result.InventoryCount++
		if result.InventoryCount > 2000 {
			return result, invalid("laundry preview supports at most 2000 active needs-wash garments")
		}
		var raw []byte
		var g Garment
		if e = rows.Scan(&raw); e != nil {
			return result, e
		}
		if e = json.Unmarshal(raw, &g); e != nil {
			return result, e
		}
		candidate := LaundryCandidate{g.ID, g.Version, g.Name}
		if why := laundryRestriction(g, in.Program); why != "" {
			result.Blocked = append(result.Blocked, LaundryBlocked{candidate, why})
			continue
		}
		key := laundryGroup(g)
		if groups[key] == nil {
			groups[key] = &LaundryGroup{ID: key, ColourGroup: g.Care.ColourGroup, Items: []LaundryCandidate{}}
		}
		groups[key].Items = append(groups[key].Items, candidate)
	}
	if e = rows.Err(); e != nil {
		return result, e
	}
	for _, group := range groups {
		result.Groups = append(result.Groups, *group)
	}
	sort.Slice(result.Groups, func(i, j int) bool { return result.Groups[i].ID < result.Groups[j].ID })
	return result, nil
}
func validateLaundryData(d *LaundryData) error {
	d.Name = strings.TrimSpace(d.Name)
	if len(d.Name) < 1 || len(d.Name) > 100 || len(d.Items) < 1 || len(d.Items) > 30 {
		return invalid("name the load and choose 1-30 garments from one compatible group")
	}
	if e := date(d.Day); e != nil {
		return e
	}
	if _, e := time.LoadLocation(d.TimeZone); e != nil || d.TimeZone == "" || d.TimeZone == "Local" || len(d.TimeZone) > 100 {
		return invalid("choose an explicit IANA time zone")
	}
	if e := validateLaundryProgram(d.Program); e != nil {
		return e
	}
	seen := map[string]bool{}
	for i := range d.Items {
		key, e := id(d.Items[i].GarmentID)
		if e != nil {
			return e
		}
		if seen[key] || d.Items[i].ExpectedVersion < 1 {
			return invalid("choose unique garments with reviewed versions")
		}
		seen[key] = true
		d.Items[i].GarmentID = key
	}
	return nil
}
func (u *unit) ensureLaundryUnreserved(ctx context.Context, key string) error {
	var reserved bool
	if e := u.tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM retro.laundry_items WHERE garment_id=$1 AND active)`, key).Scan(&reserved); e != nil {
		return e
	}
	if reserved {
		return conflict("this garment is in an active laundry load; finish or cancel the load before editing it")
	}
	return nil
}
func (u *unit) getLaundry(ctx context.Context, value string) (LaundryLoad, error) {
	var load LaundryLoad
	key, e := id(value)
	if e != nil {
		return load, e
	}
	var raw []byte
	e = u.tx.QueryRow(ctx, `SELECT id::text,version,name,day::text,time_zone,state,program,started_at,washed_at,completed_at,cancelled_at,created_at,updated_at FROM retro.laundry_loads WHERE id=$1`, key).Scan(&load.ID, &load.Version, &load.Name, &load.Day, &load.TimeZone, &load.State, &raw, &load.StartedAt, &load.WashedAt, &load.CompletedAt, &load.CancelledAt, &load.CreatedAt, &load.UpdatedAt)
	if e != nil {
		return load, e
	}
	if e = json.Unmarshal(raw, &load.Program); e != nil {
		return load, e
	}
	load.Items = []LaundryItem{}
	rows, e := u.tx.Query(ctx, `SELECT garment_id::text,expected_version,snapshot FROM retro.laundry_items WHERE load_id=$1 ORDER BY position`, key)
	if e != nil {
		return load, e
	}
	defer rows.Close()
	for rows.Next() {
		var item LaundryItem
		var snapshot []byte
		if e = rows.Scan(&item.GarmentID, &item.ExpectedVersion, &snapshot); e != nil {
			return load, e
		}
		if e = json.Unmarshal(snapshot, &item.Snapshot); e != nil {
			return load, e
		}
		load.Items = append(load.Items, item)
	}
	return load, rows.Err()
}
func (u *unit) reviewedLaundryItems(ctx context.Context, d LaundryData) ([]Garment, error) {
	garments := []Garment{}
	group := ""
	for _, item := range d.Items {
		g, e := u.getGarment(ctx, item.GarmentID)
		if e != nil {
			return nil, e
		}
		if e = version(item.ExpectedVersion, g.Version); e != nil {
			return nil, e
		}
		if why := laundryRestriction(g, d.Program); why != "" {
			return nil, conflict(why)
		}
		if e = u.ensureLaundryUnreserved(ctx, g.ID); e != nil {
			return nil, e
		}
		key := laundryGroup(g)
		if group != "" && group != key {
			return nil, conflict("split different colour groups and wash-separately garments into separate loads")
		}
		group = key
		garments = append(garments, g)
	}
	return garments, nil
}
func (u *unit) saveLaundryItems(ctx context.Context, key string, garments []Garment) error {
	if _, e := u.tx.Exec(ctx, `DELETE FROM retro.laundry_items WHERE load_id=$1`, key); e != nil {
		return e
	}
	for pos, g := range garments {
		raw, e := json.Marshal(g)
		if e != nil {
			return e
		}
		if _, e = u.tx.Exec(ctx, `INSERT INTO retro.laundry_items(load_id,garment_id,position,expected_version,snapshot) VALUES($1,$2,$3,$4,$5)`, key, g.ID, pos, g.Version, raw); e != nil {
			return e
		}
	}
	return nil
}
func createLaundry(ctx context.Context, u *unit, in CreateLaundryInput) (LaundryResult, error) {
	var result LaundryResult
	key, e := createID(in.ID)
	if e != nil {
		return result, e
	}
	if e = validateLaundryData(&in.LaundryData); e != nil {
		return result, e
	}
	garments, e := u.reviewedLaundryItems(ctx, in.LaundryData)
	if e != nil {
		return result, e
	}
	raw, e := json.Marshal(in.Program)
	if e != nil {
		return result, e
	}
	if _, e = u.tx.Exec(ctx, `INSERT INTO retro.laundry_loads(id,name,day,time_zone,program) VALUES($1,$2,$3,$4,$5)`, key, in.Name, in.Day, in.TimeZone, raw); e != nil {
		return result, e
	}
	if e = u.saveLaundryItems(ctx, key, garments); e != nil {
		return result, e
	}
	result.Load, e = u.getLaundry(ctx, key)
	if e != nil {
		return result, e
	}
	return result, u.audit(ctx, "laundry_load", key, nil, result.Load)
}
func updateLaundry(ctx context.Context, u *unit, in PatchInput) (LaundryResult, error) {
	var result LaundryResult
	before, e := u.getLaundry(ctx, in.ID)
	if e != nil {
		return result, e
	}
	if e = version(in.ExpectedVersion, before.Version); e != nil {
		return result, e
	}
	if before.State != "planned" {
		return result, conflict("only planned laundry loads can be edited")
	}
	d := LaundryData{Name: before.Name, Day: before.Day, TimeZone: before.TimeZone, Program: before.Program, Items: []LaundrySelection{}}
	for _, item := range before.Items {
		d.Items = append(d.Items, item.LaundrySelection)
	}
	for _, v := range in.Patch {
		if strings.TrimSpace(string(v)) == "null" {
			return result, invalid("laundry fields cannot be null")
		}
	}
	if e = patchFields(&d, in.Patch, "name", "day", "time_zone", "program", "items"); e != nil {
		return result, e
	}
	if e = validateLaundryData(&d); e != nil {
		return result, e
	}
	garments, e := u.reviewedLaundryItems(ctx, d)
	if e != nil {
		return result, e
	}
	raw, e := json.Marshal(d.Program)
	if e != nil {
		return result, e
	}
	if _, e = u.tx.Exec(ctx, `UPDATE retro.laundry_loads SET name=$2,day=$3,time_zone=$4,program=$5,version=version+1,updated_at=now() WHERE id=$1`, before.ID, d.Name, d.Day, d.TimeZone, raw); e != nil {
		return result, e
	}
	if e = u.saveLaundryItems(ctx, before.ID, garments); e != nil {
		return result, e
	}
	result.Load, e = u.getLaundry(ctx, before.ID)
	if e != nil {
		return result, e
	}
	return result, u.audit(ctx, "laundry_load", before.ID, before, result.Load)
}
func (u *unit) laundryAvailability(ctx context.Context, load LaundryLoad, availability string) error {
	for _, item := range load.Items {
		before, e := u.getGarment(ctx, item.GarmentID)
		if e != nil {
			return e
		}
		if e = version(item.ExpectedVersion, before.Version); e != nil {
			return e
		}
		if before.ArchivedAt != nil || before.Availability != "washing" {
			return conflict("an active laundry garment changed; review the load")
		}
		if _, e = u.tx.Exec(ctx, `UPDATE retro.garments SET availability=$2,version=version+1,updated_at=now() WHERE id=$1`, before.ID, availability); e != nil {
			return e
		}
		if _, e = u.tx.Exec(ctx, `UPDATE retro.laundry_items SET expected_version=$3,active=false WHERE load_id=$1 AND garment_id=$2`, load.ID, before.ID, before.Version+1); e != nil {
			return e
		}
		after, e := u.getGarment(ctx, before.ID)
		if e != nil {
			return e
		}
		if e = u.audit(ctx, "garment", before.ID, before, after); e != nil {
			return e
		}
	}
	return nil
}
func progressLaundry(ctx context.Context, u *unit, in EditInput) (LaundryResult, error) {
	var result LaundryResult
	before, e := u.getLaundry(ctx, in.ID)
	if e != nil {
		return result, e
	}
	if e = version(in.ExpectedVersion, before.Version); e != nil {
		return result, e
	}
	next, stamp := "", ""
	switch before.State {
	case "planned":
		d := LaundryData{Name: before.Name, Day: before.Day, TimeZone: before.TimeZone, Program: before.Program, Items: []LaundrySelection{}}
		for _, item := range before.Items {
			d.Items = append(d.Items, item.LaundrySelection)
		}
		if e = validateLaundryData(&d); e != nil {
			return result, e
		}
		zone, _ := time.LoadLocation(before.TimeZone)
		if before.Day > time.Now().In(zone).Format("2006-01-02") {
			return result, conflict("a future planned load cannot be started yet")
		}
		garments, e := u.reviewedLaundryItems(ctx, d)
		if e != nil {
			return result, e
		}
		for _, g := range garments {
			if _, e = u.tx.Exec(ctx, `UPDATE retro.garments SET availability='washing',version=version+1,updated_at=now() WHERE id=$1`, g.ID); e != nil {
				return result, e
			}
			if _, e = u.tx.Exec(ctx, `UPDATE retro.laundry_items SET expected_version=$3,active=true WHERE load_id=$1 AND garment_id=$2`, before.ID, g.ID, g.Version+1); e != nil {
				return result, e
			}
			after, e := u.getGarment(ctx, g.ID)
			if e != nil {
				return result, e
			}
			if e = u.audit(ctx, "garment", g.ID, g, after); e != nil {
				return result, e
			}
		}
		next, stamp = "washing", "started_at"
	case "washing":
		next, stamp = "drying", "washed_at"
		if before.Program.WashMethod == "dry_clean" {
			if e = u.laundryAvailability(ctx, before, "ready"); e != nil {
				return result, e
			}
			next = "completed"
		}
	case "drying":
		if e = u.laundryAvailability(ctx, before, "ready"); e != nil {
			return result, e
		}
		next, stamp = "completed", "completed_at"
	default:
		return result, conflict("this laundry load has no further progress step")
	}
	// stamp is selected only by the state machine, never from caller input.
	query := `UPDATE retro.laundry_loads SET state=$2,` + stamp + `=now(),version=version+1,updated_at=now()`
	if before.State == "washing" && next == "completed" {
		query += `,completed_at=now()`
	}
	query += ` WHERE id=$1`
	if _, e = u.tx.Exec(ctx, query, before.ID, next); e != nil {
		return result, e
	}
	result.Load, e = u.getLaundry(ctx, before.ID)
	if e != nil {
		return result, e
	}
	return result, u.audit(ctx, "laundry_load", before.ID, before, result.Load)
}
func cancelLaundry(ctx context.Context, u *unit, in EditInput) (LaundryResult, error) {
	var result LaundryResult
	before, e := u.getLaundry(ctx, in.ID)
	if e != nil {
		return result, e
	}
	if e = version(in.ExpectedVersion, before.Version); e != nil {
		return result, e
	}
	if !oneOf(before.State, "planned", "washing", "drying") {
		return result, conflict("only unfinished laundry loads can be cancelled")
	}
	if before.State != "planned" {
		if e = u.laundryAvailability(ctx, before, "needs_wash"); e != nil {
			return result, e
		}
	}
	if _, e = u.tx.Exec(ctx, `UPDATE retro.laundry_loads SET state='cancelled',cancelled_at=now(),version=version+1,updated_at=now() WHERE id=$1`, before.ID); e != nil {
		return result, e
	}
	result.Load, e = u.getLaundry(ctx, before.ID)
	if e != nil {
		return result, e
	}
	return result, u.audit(ctx, "laundry_load", before.ID, before, result.Load)
}
func listLaundry(ctx context.Context, u *unit, in LaundryListInput) (Page[LaundryLoad], error) {
	result := Page[LaundryLoad]{Items: []LaundryLoad{}}
	filters := in
	filters.ListInput = ListInput{}
	limit, after, _, e := page(in.ListInput, filters)
	if e != nil {
		return result, e
	}
	if in.State != "" && !oneOf(in.State, "planned", "washing", "drying", "completed", "cancelled") {
		return result, invalid("unsupported laundry state")
	}
	if in.GarmentID != "" {
		if in.GarmentID, e = id(in.GarmentID); e != nil {
			return result, e
		}
	}
	rows, e := u.tx.Query(ctx, `SELECT l.id::text FROM retro.laundry_loads l WHERE ($1='' OR state=$1) AND ($2='' OR EXISTS(SELECT 1 FROM retro.laundry_items i WHERE i.load_id=l.id AND i.garment_id=NULLIF($2,'')::uuid)) AND ($3='' OR l.id>NULLIF($3,'')::uuid) ORDER BY l.id LIMIT $4`, in.State, in.GarmentID, after, limit+1)
	if e != nil {
		return result, e
	}
	keys := []string{}
	for rows.Next() {
		var key string
		if e = rows.Scan(&key); e != nil {
			rows.Close()
			return result, e
		}
		keys = append(keys, key)
	}
	e = rows.Err()
	rows.Close()
	if e != nil {
		return result, e
	}
	if len(keys) > limit {
		keys = keys[:limit]
		result.NextCursor = cursor(filters, keys[len(keys)-1], "")
	}
	for _, key := range keys {
		load, e := u.getLaundry(ctx, key)
		if e != nil {
			return result, e
		}
		result.Items = append(result.Items, load)
	}
	return result, nil
}
