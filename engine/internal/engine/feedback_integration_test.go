package engine_test

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/nighthawklabs/retro/engine/internal/engine"
)

func TestIntegrationCareSnapshotsAndFeedbackLifecycle(t *testing.T) {
	s := integrationService(t, nil)
	care := map[string]any{"wash_method": "machine", "max_temp_c": 30, "cycle": "gentle", "confirmed": true}
	g := execute[engine.GarmentResult](t, s, "garments_create", map[string]any{"idempotency_key": uuid.NewString(), "name": "Care test", "category": "top", "care": care}).Garment
	o := execute[engine.OutfitResult](t, s, "outfits_create", map[string]any{"idempotency_key": uuid.NewString(), "day": time.Now().UTC().Format("2006-01-02"), "time_zone": "UTC", "state": "planned", "items": []engine.Selection{{GarmentID: g.ID, Role: "base"}}}).Outfit
	initial := execute[engine.FeedbackResult](t, s, "outfits_feedback_get", map[string]any{"id": o.ID})
	body := edit(initial.Feedback.ID, 0)
	body["outfit_id"], body["expected_outfit_version"], body["patch"] = o.ID, o.Version, map[string]any{"rating": 5}
	errorCode(t, s, "outfits_feedback_update", body, "conflict")
	o = execute[engine.OutfitResult](t, s, "outfits_confirm", edit(o.ID, o.Version)).Outfit
	if o.Items[0].Snapshot.Care == nil || !o.Items[0].Snapshot.Care.Confirmed {
		t.Fatal("wear snapshot lost care")
	}
	body["idempotency_key"], body["expected_outfit_version"] = uuid.NewString(), o.Version
	f := execute[engine.FeedbackResult](t, s, "outfits_feedback_update", body).Feedback
	retried := execute[engine.FeedbackResult](t, s, "outfits_feedback_update", body).Feedback
	if f.Version != 1 || retried.Version != 1 {
		t.Fatal("feedback retry advanced version")
	}
	correction := edit(o.ID, o.Version)
	correction["patch"] = map[string]any{"notes": "Corrected"}
	o = execute[engine.OutfitResult](t, s, "outfits_update", correction).Outfit
	read := execute[engine.FeedbackResult](t, s, "outfits_feedback_get", map[string]any{"id": o.ID})
	if read.Feedback.OutfitVersion == read.CurrentOutfitVersion {
		t.Fatal("old feedback was silently relabelled")
	}
	reset := edit(f.ID, f.Version)
	reset["outfit_id"], reset["expected_outfit_version"], reset["patch"] = o.ID, o.Version-1, map[string]any{"rating": nil}
	errorCode(t, s, "outfits_feedback_update", reset, "conflict")
	o = execute[engine.OutfitResult](t, s, "outfits_void", edit(o.ID, o.Version)).Outfit
	reset["expected_outfit_version"] = o.Version
	errorCode(t, s, "outfits_feedback_update", reset, "conflict")
	o = execute[engine.OutfitResult](t, s, "outfits_restore", edit(o.ID, o.Version)).Outfit
	reset["expected_outfit_version"] = o.Version
	cleared := execute[engine.FeedbackResult](t, s, "outfits_feedback_update", reset).Feedback
	if cleared.Rating != nil || cleared.Version != 2 {
		t.Fatal("feedback reset failed")
	}
	latest := execute[engine.OutfitResult](t, s, "outfits_get", map[string]any{"id": o.ID}).Outfit
	if latest.Version != o.Version || latest.State != "worn" {
		t.Fatal("feedback changed wear history")
	}
	audit := execute[engine.Page[engine.Change]](t, s, "history_list", map[string]any{"entity_type": "feedback", "id": f.ID})
	if len(audit.Items) != 2 {
		t.Fatal("feedback audit missing or retry duplicated it")
	}
	requestID := uuid.NewString()
	context := execute[engine.WardrobeContext](t, s, "wardrobe_context_get", map[string]any{"request_id": requestID, "garment_ids": []string{g.ID}, "outfit_ids": []string{o.ID}})
	if context.RequestID != requestID || context.SchemaVersion != 1 || context.Coverage != "explicit_records_only" || len(context.Sources) != 4 || len(context.Garments) != 1 || len(context.Outfits) != 1 || context.Feedback[0].Feedback.Version != cleared.Version {
		t.Fatal("context lost identity, coverage or source versions")
	}
	if context.Garments[0].Care == nil || !context.Garments[0].Care.Confirmed {
		t.Fatal("context lost reviewed care")
	}
	errorCode(t, s, "wardrobe_context_get", map[string]any{"request_id": requestID, "garment_ids": []string{g.ID, g.ID}}, "invalid_input")
}
