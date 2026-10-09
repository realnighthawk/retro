package engine_test

import (
	"github.com/google/uuid"
	"github.com/nighthawklabs/retro/engine/internal/engine"
	"testing"
	"time"
)

func TestIntegrationLaundryReservationsProgressAndSnapshots(t *testing.T) {
	s := integrationService(t, nil)
	temp := 20
	program := engine.LaundryProgram{WashMethod: "machine", TemperatureC: &temp, Cycle: "gentle", Drying: "line"}
	create := func(colour string) engine.Garment {
		return execute[engine.GarmentResult](t, s, "garments_create", map[string]any{"idempotency_key": uuid.NewString(), "name": "Laundry fixture", "category": "top", "availability": "needs_wash", "care": engine.CareSettings{WashMethod: "machine", MaxTempC: &temp, Cycle: "gentle", ColourGroup: colour, Drying: "line", Confirmed: true, Source: "manual"}}).Garment
	}
	dark, white := create("dark"), create("white")
	before := execute[engine.Analysis](t, s, "wardrobe_analyze", map[string]any{})
	plan := func(g engine.Garment) map[string]any {
		return map[string]any{"id": uuid.NewString(), "idempotency_key": uuid.NewString(), "name": "Cold wash", "day": time.Now().UTC().Format("2006-01-02"), "time_zone": "UTC", "program": program, "items": []engine.LaundrySelection{{GarmentID: g.ID, ExpectedVersion: g.Version}}}
	}
	mixed := plan(dark)
	mixed["items"] = []engine.LaundrySelection{{GarmentID: dark.ID, ExpectedVersion: dark.Version}, {GarmentID: white.ID, ExpectedVersion: white.Version}}
	errorCode(t, s, "laundry_create", mixed, "conflict")
	body := plan(dark)
	load := execute[engine.LaundryResult](t, s, "laundry_create", body).Load
	if execute[engine.LaundryResult](t, s, "laundry_create", body).Load.ID != load.ID {
		t.Fatal("create replay duplicated load")
	}
	other := execute[engine.LaundryResult](t, s, "laundry_create", plan(dark)).Load
	start := edit(load.ID, load.Version)
	washing := execute[engine.LaundryResult](t, s, "laundry_progress", start).Load
	if execute[engine.LaundryResult](t, s, "laundry_progress", start).Load.Version != washing.Version {
		t.Fatal("start replay advanced twice")
	}
	current := execute[engine.GarmentResult](t, s, "garments_get", map[string]any{"id": dark.ID}).Garment
	if current.Availability != "washing" || current.Version != dark.Version+1 {
		t.Fatal("start did not reserve garments")
	}
	errorCode(t, s, "laundry_progress", edit(other.ID, other.Version), "conflict")
	change := edit(current.ID, current.Version)
	change["patch"] = map[string]any{"availability": "ready"}
	errorCode(t, s, "garments_update", change, "conflict")
	errorCode(t, s, "garments_archive", edit(current.ID, current.Version), "conflict")
	drying := execute[engine.LaundryResult](t, s, "laundry_progress", edit(washing.ID, washing.Version)).Load
	if drying.State != "drying" || drying.WashedAt == nil || execute[engine.GarmentResult](t, s, "garments_get", map[string]any{"id": dark.ID}).Garment.Availability != "washing" {
		t.Fatal("wash prematurely made wet garments ready")
	}
	completed := execute[engine.LaundryResult](t, s, "laundry_progress", edit(drying.ID, drying.Version)).Load
	current = execute[engine.GarmentResult](t, s, "garments_get", map[string]any{"id": dark.ID}).Garment
	if completed.State != "completed" || completed.CompletedAt == nil || current.Availability != "ready" || completed.Items[0].Snapshot.Version != dark.Version {
		t.Fatal("completion lost snapshot or availability")
	}
	change = edit(current.ID, current.Version)
	change["patch"] = map[string]any{"name": "Renamed after washing"}
	_ = execute[engine.GarmentResult](t, s, "garments_update", change)
	retained := execute[engine.LaundryResult](t, s, "laundry_get", map[string]any{"id": load.ID}).Load
	if retained.Items[0].Snapshot.Name != dark.Name {
		t.Fatal("inventory edit rewrote wash history")
	}
	history := execute[engine.Page[engine.Change]](t, s, "history_list", map[string]any{"entity_type": "laundry_load", "id": load.ID})
	if len(history.Items) != 4 {
		t.Fatal("replay duplicated laundry history")
	}
	listed := execute[engine.Page[engine.LaundryLoad]](t, s, "laundry_list", map[string]any{"garment_id": dark.ID, "state": "completed"})
	if len(listed.Items) != 1 || listed.Items[0].ID != load.ID {
		t.Fatal("garment wash history missing")
	}
	after := execute[engine.Analysis](t, s, "wardrobe_analyze", map[string]any{})
	if before.OutfitEvents != after.OutfitEvents || before.WearDays != after.WearDays {
		t.Fatal("laundry created wear history")
	}
	whiteLoad := execute[engine.LaundryResult](t, s, "laundry_create", plan(white)).Load
	whiteLoad = execute[engine.LaundryResult](t, s, "laundry_progress", edit(whiteLoad.ID, whiteLoad.Version)).Load
	cancelled := execute[engine.LaundryResult](t, s, "laundry_cancel", edit(whiteLoad.ID, whiteLoad.Version)).Load
	current = execute[engine.GarmentResult](t, s, "garments_get", map[string]any{"id": white.ID}).Garment
	if cancelled.CompletedAt != nil || cancelled.CancelledAt == nil || current.Availability != "needs_wash" {
		t.Fatal("cancellation falsely completed laundry")
	}
}

func TestIntegrationLaundryStalePiecesAndProfessionalReturn(t *testing.T) {
	s := integrationService(t, nil)
	temp := 20
	makeGarment := func(method, drying string, max *int) engine.Garment {
		return execute[engine.GarmentResult](t, s, "garments_create", map[string]any{"idempotency_key": uuid.NewString(), "name": "Care fixture", "category": "top", "availability": "needs_wash", "care": engine.CareSettings{WashMethod: method, MaxTempC: max, Cycle: "unknown", ColourGroup: "dark", Drying: drying, Source: "manual", Confirmed: true}}).Garment
	}
	a, b := makeGarment("hand", "line", &temp), makeGarment("hand", "line", &temp)
	body := map[string]any{"idempotency_key": uuid.NewString(), "name": "Hand wash", "day": time.Now().UTC().Format("2006-01-02"), "time_zone": "UTC", "program": engine.LaundryProgram{WashMethod: "hand", TemperatureC: &temp, Cycle: "unknown", Drying: "line"}, "items": []engine.LaundrySelection{{GarmentID: a.ID, ExpectedVersion: a.Version}, {GarmentID: b.ID, ExpectedVersion: b.Version}}}
	load := execute[engine.LaundryResult](t, s, "laundry_create", body).Load
	change := edit(b.ID, b.Version)
	change["patch"] = map[string]any{"name": "Changed before washing"}
	b = execute[engine.GarmentResult](t, s, "garments_update", change).Garment
	errorCode(t, s, "laundry_progress", edit(load.ID, load.Version), "conflict")
	if execute[engine.GarmentResult](t, s, "garments_get", map[string]any{"id": a.ID}).Garment.Availability != "needs_wash" {
		t.Fatal("failed start partially reserved the first piece")
	}
	change = edit(load.ID, load.Version)
	change["patch"] = map[string]any{"items": []engine.LaundrySelection{{GarmentID: a.ID, ExpectedVersion: a.Version}, {GarmentID: b.ID, ExpectedVersion: b.Version}}}
	load = execute[engine.LaundryResult](t, s, "laundry_update", change).Load
	load = execute[engine.LaundryResult](t, s, "laundry_progress", edit(load.ID, load.Version)).Load
	_ = execute[engine.LaundryResult](t, s, "laundry_cancel", edit(load.ID, load.Version))
	professional := makeGarment("dry_clean", "professional", nil)
	body["idempotency_key"] = uuid.NewString()
	body["name"] = "Professional care"
	body["program"] = engine.LaundryProgram{WashMethod: "dry_clean", Cycle: "unknown", Drying: "professional"}
	body["items"] = []engine.LaundrySelection{{GarmentID: professional.ID, ExpectedVersion: professional.Version}}
	load = execute[engine.LaundryResult](t, s, "laundry_create", body).Load
	load = execute[engine.LaundryResult](t, s, "laundry_progress", edit(load.ID, load.Version)).Load
	load = execute[engine.LaundryResult](t, s, "laundry_progress", edit(load.ID, load.Version)).Load
	if load.State != "completed" || load.WashedAt == nil || load.CompletedAt == nil {
		t.Fatal("professional return invented an extra home drying stage")
	}
}
