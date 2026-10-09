package engine_test

import (
	"testing"

	"github.com/google/uuid"
	"github.com/nighthawklabs/retro/engine/internal/engine"
)

func TestIntegrationPairingsReplayLinkBrowseAndKeepCurrentFacts(t *testing.T) {
	s := integrationService(t, nil)
	create := func(category string) engine.Garment {
		return execute[engine.GarmentResult](t, s, "garments_create", map[string]any{"idempotency_key": uuid.NewString(), "name": "Pairing test " + category, "category": category}).Garment
	}
	top, bottom := create("top"), create("bottom")
	before := execute[engine.Analysis](t, s, "wardrobe_analyze", map[string]any{})
	body := map[string]any{"id": uuid.NewString(), "idempotency_key": uuid.NewString(), "name": "Test pairing", "items": []engine.Selection{{GarmentID: top.ID, Role: "base"}, {GarmentID: bottom.ID, Role: "bottom"}}}
	p := execute[engine.PairingResult](t, s, "pairings_create", body).Pairing
	replay := execute[engine.PairingResult](t, s, "pairings_create", body).Pairing
	if p.ID != replay.ID || p.Version != replay.Version {
		t.Fatal("create replay duplicated the pairing")
	}
	audit := execute[engine.Page[engine.Change]](t, s, "history_list", map[string]any{"entity_type": "pairing", "id": p.ID})
	if len(audit.Items) != 1 {
		t.Fatal("create replay wrote another audit row")
	}
	listed := execute[engine.Page[engine.Pairing]](t, s, "pairings_list", map[string]any{"garment_id": top.ID})
	if len(listed.Items) != 1 || listed.Items[0].ID != p.ID {
		t.Fatal("garment-linked browse lost the pairing")
	}
	wrong := edit(p.ID, p.Version)
	wrong["patch"] = map[string]any{"items": []engine.Selection{{GarmentID: top.ID, Role: "base"}, {GarmentID: uuid.NewString(), Role: "feet"}}}
	errorCode(t, s, "pairings_update", wrong, "not_found")
	unchanged := execute[engine.PairingResult](t, s, "pairings_get", map[string]any{"id": p.ID}).Pairing
	if unchanged.Version != p.Version || len(unchanged.Items) != 2 {
		t.Fatal("failed piece replacement was not rolled back")
	}
	editGarment := edit(top.ID, top.Version)
	editGarment["patch"] = map[string]any{"name": "Renamed pairing top", "availability": "washing"}
	updated := execute[engine.GarmentResult](t, s, "garments_update", editGarment).Garment
	current := execute[engine.PairingResult](t, s, "pairings_get", map[string]any{"id": p.ID}).Pairing
	if current.Version != p.Version || current.Items[0].Snapshot.Version != updated.Version || current.Items[0].Snapshot.Availability != "washing" {
		t.Fatal("pairing returned stale garment snapshots")
	}
	archived := execute[engine.PairingResult](t, s, "pairings_archive", edit(p.ID, p.Version)).Pairing
	listed = execute[engine.Page[engine.Pairing]](t, s, "pairings_list", map[string]any{"garment_id": top.ID})
	if len(listed.Items) != 0 {
		t.Fatal("archived pairing leaked into active browse")
	}
	listed = execute[engine.Page[engine.Pairing]](t, s, "pairings_list", map[string]any{"garment_id": top.ID, "include_archived": true})
	if len(listed.Items) != 1 {
		t.Fatal("archived pairing was erased")
	}
	restored := execute[engine.PairingResult](t, s, "pairings_restore", edit(p.ID, archived.Version)).Pairing
	patch := edit(p.ID, p.Version)
	patch["patch"] = map[string]any{"notes": "stale"}
	errorCode(t, s, "pairings_update", patch, "conflict")
	patch = edit(p.ID, restored.Version)
	patch["patch"] = map[string]any{"notes": "reviewed"}
	_ = execute[engine.PairingResult](t, s, "pairings_update", patch)
	after := execute[engine.Analysis](t, s, "wardrobe_analyze", map[string]any{})
	if before.OutfitEvents != after.OutfitEvents || before.WearDays != after.WearDays {
		t.Fatal("saving pairings changed wear history")
	}
}

func TestIntegrationDailySelectionIsStableVersionedAndSeparateFromWear(t *testing.T) {
	s := integrationService(t, nil)
	day := "1901-01-02"
	g := execute[engine.GarmentResult](t, s, "garments_create", map[string]any{"idempotency_key": uuid.NewString(), "name": "Daily plan dress", "category": "one_piece"}).Garment
	o := execute[engine.OutfitResult](t, s, "outfits_create", map[string]any{"idempotency_key": uuid.NewString(), "day": day, "time_zone": "UTC", "state": "planned", "items": []engine.Selection{{GarmentID: g.ID, Role: "one_piece"}}}).Outfit
	d := execute[engine.DayResult](t, s, "wardrobe_day_get", map[string]any{"day": day})
	body := edit(d.Selection.ID, d.Selection.Version)
	body["day"] = day
	body["outfit_id"] = o.ID
	body["expected_outfit_version"] = o.Version
	choice := execute[engine.DaySelectionResult](t, s, "wardrobe_day_selection_update", body).Selection
	replay := execute[engine.DaySelectionResult](t, s, "wardrobe_day_selection_update", body).Selection
	if choice.Version != replay.Version || choice.Version != d.Selection.Version+1 {
		t.Fatal("selection replay changed the daily version")
	}
	errorCode(t, s, "wardrobe_day_selection_update", map[string]any{"idempotency_key": uuid.NewString(), "id": choice.ID, "day": day, "expected_version": d.Selection.Version, "outfit_id": nil}, "conflict")
	for i := 0; i < 2; i++ {
		_ = execute[engine.Suggestions](t, s, "wardrobe_suggest", map[string]any{"day": day, "variant": i})
		refreshed := execute[engine.DayResult](t, s, "wardrobe_day_get", map[string]any{"day": day})
		if refreshed.Selection.OutfitID == nil || *refreshed.Selection.OutfitID != o.ID || refreshed.Selection.Version != choice.Version || refreshed.Selection.Outfit.State != "planned" || len(refreshed.Outfits) != len(d.Outfits) {
			t.Fatal("refresh rewrote the chosen plan or recorded wear")
		}
	}
	updated := execute[engine.OutfitResult](t, s, "outfits_update", map[string]any{"idempotency_key": uuid.NewString(), "id": o.ID, "expected_version": o.Version, "patch": map[string]any{"label": "Reviewed plan"}}).Outfit
	stale := edit(choice.ID, choice.Version)
	stale["day"] = day
	stale["outfit_id"] = o.ID
	stale["expected_outfit_version"] = o.Version
	errorCode(t, s, "wardrobe_day_selection_update", stale, "conflict")
	worn := execute[engine.OutfitResult](t, s, "outfits_confirm", edit(updated.ID, updated.Version)).Outfit
	refreshed := execute[engine.DayResult](t, s, "wardrobe_day_get", map[string]any{"day": day})
	if refreshed.Selection.Outfit.State != "worn" || refreshed.Selection.Version != choice.Version {
		t.Fatal("confirmation replaced the daily identity")
	}
	_ = execute[engine.OutfitResult](t, s, "outfits_void", edit(worn.ID, worn.Version))
	refreshed = execute[engine.DayResult](t, s, "wardrobe_day_get", map[string]any{"day": day})
	if refreshed.Selection.OutfitID == nil || refreshed.Selection.Problem == nil {
		t.Fatal("void silently erased the selected reference")
	}
	clear := edit(choice.ID, choice.Version)
	clear["day"] = day
	clear["outfit_id"] = nil
	cleared := execute[engine.DaySelectionResult](t, s, "wardrobe_day_selection_update", clear).Selection
	if cleared.OutfitID != nil || cleared.Version != choice.Version+1 {
		t.Fatal("clear lost the versioned tombstone")
	}
	retained := execute[engine.OutfitResult](t, s, "outfits_get", map[string]any{"id": o.ID}).Outfit
	if retained.State != "void" {
		t.Fatal("clear changed outfit history")
	}
}
