package engine_test

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/nighthawklabs/retro/engine/internal/engine"
)

func TestIntegrationLaundryCheckInUsesCompletedCleaningAndCurrentWearHistory(t *testing.T) {
	s := integrationService(t, nil)
	ctx := context.Background()
	pool, e := pgxpool.New(ctx, os.Getenv("TEST_DATABASE_URL"))
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(pool.Close)
	temp, wears, days := 20, 2, 7
	g := execute[engine.GarmentResult](t, s, "garments_create", map[string]any{"idempotency_key": uuid.NewString(), "name": "Check-in fixture", "category": "top", "availability": "needs_wash", "laundry_reminder": engine.LaundryReminder{WearDays: &wears, IntervalDays: &days}, "care": engine.CareSettings{WashMethod: "hand", MaxTempC: &temp, Cycle: "unknown", ColourGroup: "dark", Drying: "line", Source: "manual", Confirmed: true}}).Garment
	read := func() engine.LaundryCheckInItem {
		return execute[engine.LaundryCheckIn](t, s, "laundry_check_in", map[string]any{"garment_id": g.ID, "time_zone": "America/Los_Angeles"}).Items[0]
	}
	if value := read(); value.Wears != nil || value.LastCleaning != nil || value.Due {
		t.Fatal("missing baseline became known zero or due")
	}
	plan := func(garment engine.Garment) engine.LaundryLoad {
		return execute[engine.LaundryResult](t, s, "laundry_create", map[string]any{"idempotency_key": uuid.NewString(), "name": "Hand wash", "day": "2001-01-02", "time_zone": "UTC", "program": engine.LaundryProgram{WashMethod: "hand", TemperatureC: &temp, Cycle: "unknown", Drying: "line"}, "items": []engine.LaundrySelection{{GarmentID: garment.ID, ExpectedVersion: garment.Version}}}).Load
	}
	load := plan(g)
	for n := 0; n < 3; n++ {
		load = execute[engine.LaundryResult](t, s, "laundry_progress", edit(load.ID, load.Version)).Load
	}
	// Retimestamp only this disposable fixture to author date-order/time-zone cases without waiting days.
	cleaned := time.Date(2001, 1, 2, 15, 30, 0, 0, time.UTC)
	if _, e = pool.Exec(ctx, `UPDATE retro.laundry_loads SET started_at=$2,washed_at=$3,completed_at=$4 WHERE id=$1`, load.ID, cleaned.Add(-2*time.Hour), cleaned.Add(-time.Hour), cleaned); e != nil {
		t.Fatal(e)
	}
	wear := func(day, zone, state string) engine.Outfit {
		return execute[engine.OutfitResult](t, s, "outfits_create", map[string]any{"idempotency_key": uuid.NewString(), "day": day, "time_zone": zone, "state": state, "items": []engine.Selection{{GarmentID: g.ID, Role: "base"}}}).Outfit
	}
	_ = wear("2001-01-01", "UTC", "worn") // A newly logged backdated wear stays before cleaning.
	_ = wear("2001-01-02", "America/Los_Angeles", "worn")
	_ = wear("2001-01-03", "Asia/Tokyo", "worn") // Cleaning was already Jan 3 in Tokyo.
	after := wear("2001-01-03", "America/Los_Angeles", "worn")
	corrected := wear("2001-01-04", "UTC", "worn")
	_ = wear("2001-01-04", "UTC", "worn")
	_ = wear("2001-01-05", "UTC", "planned")
	value := read()
	if value.Wears == nil || value.Wears.WearDays != 2 || value.Wears.WearEvents != 3 || value.Wears.SameDayWearDays != 2 || value.Wears.SameDayWearEvents != 2 || !value.Due || len(value.DueReasons) != 2 {
		t.Fatalf("wrong date-based check-in: %+v", value)
	}
	after = execute[engine.OutfitResult](t, s, "outfits_void", edit(after.ID, after.Version)).Outfit
	if value = read(); value.Wears.WearDays != 1 || value.Wears.WearEvents != 2 || len(value.DueReasons) != 1 || value.DueReasons[0] != "interval_threshold" {
		t.Fatal("void wear remained in threshold count")
	}
	after = execute[engine.OutfitResult](t, s, "outfits_restore", edit(after.ID, after.Version)).Outfit
	if read().Wears.WearDays != 2 {
		t.Fatal("restored wear was not counted")
	}
	patch := edit(after.ID, after.Version)
	patch["patch"] = map[string]any{"day": "2001-01-01"}
	_ = execute[engine.OutfitResult](t, s, "outfits_update", patch)
	if read().Wears.WearDays != 1 {
		t.Fatal("corrected date did not update the count")
	}
	other := execute[engine.GarmentResult](t, s, "garments_create", map[string]any{"idempotency_key": uuid.NewString(), "name": "Corrected actual piece", "category": "top"}).Garment
	patch = edit(corrected.ID, corrected.Version)
	patch["patch"] = map[string]any{"items": []engine.Selection{{GarmentID: other.ID, Role: "base"}}}
	_ = execute[engine.OutfitResult](t, s, "outfits_update", patch)
	if value = read(); value.Wears.WearDays != 1 || value.Wears.WearEvents != 1 {
		t.Fatal("corrected actual pieces did not update the count")
	}
	g = execute[engine.GarmentResult](t, s, "garments_get", map[string]any{"id": g.ID}).Garment
	patch = edit(g.ID, g.Version)
	patch["patch"] = map[string]any{"availability": "needs_wash"}
	g = execute[engine.GarmentResult](t, s, "garments_update", patch).Garment
	active := plan(g)
	active = execute[engine.LaundryResult](t, s, "laundry_progress", edit(active.ID, active.Version)).Load
	if value = read(); value.Due || value.LastCleaning.ID != load.ID {
		t.Fatal("active load reset baseline or kept prompting")
	}
	_ = execute[engine.LaundryResult](t, s, "laundry_cancel", edit(active.ID, active.Version))
	if value = read(); !value.Due || value.LastCleaning.ID != load.ID {
		t.Fatal("cancelled load falsely reset cleaning")
	}
	g = execute[engine.GarmentResult](t, s, "garments_get", map[string]any{"id": g.ID}).Garment
	latest := plan(g)
	for n := 0; n < 3; n++ {
		latest = execute[engine.LaundryResult](t, s, "laundry_progress", edit(latest.ID, latest.Version)).Load
	}
	if value = read(); value.LastCleaning.ID != latest.ID || value.Wears.WearDays != 0 || value.Due {
		t.Fatal("new completed cleaning did not reset baseline")
	}
	g = execute[engine.GarmentResult](t, s, "garments_get", map[string]any{"id": g.ID}).Garment
	patch = edit(g.ID, g.Version)
	patch["patch"] = map[string]any{"laundry_reminder": nil}
	g = execute[engine.GarmentResult](t, s, "garments_update", patch).Garment
	if execute[engine.GarmentResult](t, s, "garments_update", patch).Garment.Version != g.Version || read().Reminder != nil {
		t.Fatal("reminder removal did not replay immutably")
	}
	stale := edit(g.ID, g.Version-1)
	stale["patch"] = map[string]any{"laundry_reminder": engine.LaundryReminder{WearDays: &wears}}
	errorCode(t, s, "garments_update", stale, "conflict")
	g = execute[engine.GarmentResult](t, s, "garments_archive", edit(g.ID, g.Version)).Garment
	if value = read(); value.ArchivedAt == nil || value.Due {
		t.Fatal("explicit archived check-in lost history or prompted")
	}
	all := execute[engine.LaundryCheckIn](t, s, "laundry_check_in", map[string]any{"time_zone": "UTC"})
	for _, item := range all.Items {
		if item.GarmentID == g.ID {
			t.Fatal("archived garment entered active check-in")
		}
	}
	errorCode(t, s, "laundry_check_in", map[string]any{"time_zone": "Local"}, "invalid_input")
	errorCode(t, s, "laundry_check_in", map[string]any{"time_zone": "UTC", "garment_id": uuid.NewString()}, "not_found")
}
