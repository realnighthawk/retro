package engine_test

import (
	"github.com/google/uuid"
	"github.com/nighthawklabs/retro/engine/internal/engine"
	"testing"
)

func TestIntegrationRankingUsesOnlyAsOfVersionMatchedWearsAndDoesNotWritePlans(t *testing.T) {
	s := integrationService(t, nil)
	before := execute[engine.PreferencesResult](t, s, "preferences_get", map[string]any{}).Preferences
	t.Cleanup(func() {
		current := execute[engine.PreferencesResult](t, s, "preferences_get", map[string]any{}).Preferences
		body := edit(current.ID, current.Version)
		body["patch"] = before.PreferencesData
		_ = execute[engine.PreferencesResult](t, s, "preferences_update", body)
	})
	patch := edit(before.ID, before.Version)
	patch["patch"] = map[string]any{"preferred_colours": []string{}, "avoided_colours": []string{}, "preferred_styles": []string{}, "default_occasion": "casual", "avoid_repeat_days": 0, "prefer_underused_items": false, "layering_preference": "minimal", "variety": "low"}
	p := execute[engine.PreferencesResult](t, s, "preferences_update", patch).Preferences
	create := func(category string) engine.Garment {
		return execute[engine.GarmentResult](t, s, "garments_create", map[string]any{"idempotency_key": uuid.NewString(), "name": "Ranking test " + category, "category": category}).Garment
	}
	dress, shoes := create("one_piece"), create("footwear")
	query := map[string]any{"day": "1900-01-02", "required_ids": []string{dress.ID, shoes.ID}, "expected_preferences_version": p.Version}
	initial := execute[engine.Suggestions](t, s, "wardrobe_suggest", query)
	if initial.Algorithm != "rules-v2" || initial.EffectiveOccasion != "casual" || initial.PreferencesSource.Version != p.Version || len(initial.Items) != 1 {
		t.Fatalf("ranking metadata or locked choices missing: %+v", initial)
	}
	dayBefore := execute[engine.DayResult](t, s, "wardrobe_day_get", map[string]any{"day": "1900-01-02"})
	_ = execute[engine.Suggestions](t, s, "wardrobe_suggest", query)
	dayAfter := execute[engine.DayResult](t, s, "wardrobe_day_get", map[string]any{"day": "1900-01-02"})
	if len(dayBefore.Outfits) != len(dayAfter.Outfits) {
		t.Fatal("reading suggestions created an outfit")
	}
	selections := []engine.Selection{}
	for _, item := range initial.Items[0].Items {
		selections = append(selections, item.Selection)
	}
	wear := execute[engine.OutfitResult](t, s, "outfits_create", map[string]any{"idempotency_key": uuid.NewString(), "day": "1900-01-01", "time_zone": "UTC", "state": "worn", "items": selections}).Outfit
	feedback := execute[engine.FeedbackResult](t, s, "outfits_feedback_get", map[string]any{"id": wear.ID}).Feedback
	body := edit(feedback.ID, 0)
	body["outfit_id"] = wear.ID
	body["expected_outfit_version"] = wear.Version
	body["patch"] = map[string]any{"rating": 5}
	_ = execute[engine.FeedbackResult](t, s, "outfits_feedback_update", body)
	rated := execute[engine.Suggestions](t, s, "wardrobe_suggest", query)
	if rated.Items[0].Score <= initial.Items[0].Score || rated.FeedbackSamples != initial.FeedbackSamples+1 {
		t.Fatal("explicit rated wear did not affect ranking")
	}
	_ = execute[engine.OutfitResult](t, s, "outfits_create", map[string]any{"idempotency_key": uuid.NewString(), "day": "1900-12-01", "time_zone": "UTC", "state": "worn", "items": selections})
	future := execute[engine.Suggestions](t, s, "wardrobe_suggest", query)
	if future.Items[0].Score != rated.Items[0].Score || future.FeedbackSamples != rated.FeedbackSamples {
		t.Fatal("future wear leaked into earlier-date ranking")
	}
	_ = execute[engine.OutfitResult](t, s, "outfits_update", map[string]any{"id": wear.ID, "expected_version": wear.Version, "idempotency_key": uuid.NewString(), "patch": map[string]any{"notes": "Corrected after rating"}})
	corrected := execute[engine.Suggestions](t, s, "wardrobe_suggest", query)
	if corrected.Items[0].Score != initial.Items[0].Score || corrected.FeedbackSamples != initial.FeedbackSamples {
		t.Fatal("feedback for an older outfit revision still ranked the corrected wear")
	}
	latest := execute[engine.OutfitResult](t, s, "outfits_get", map[string]any{"id": wear.ID}).Outfit
	currentFeedback := execute[engine.FeedbackResult](t, s, "outfits_feedback_get", map[string]any{"id": wear.ID}).Feedback
	body = edit(currentFeedback.ID, currentFeedback.Version)
	body["outfit_id"] = wear.ID
	body["expected_outfit_version"] = latest.Version
	body["patch"] = map[string]any{"rating": 5}
	_ = execute[engine.FeedbackResult](t, s, "outfits_feedback_update", body)
	_ = execute[engine.OutfitResult](t, s, "outfits_void", edit(wear.ID, latest.Version))
	voided := execute[engine.Suggestions](t, s, "wardrobe_suggest", query)
	if voided.Items[0].Score != initial.Items[0].Score || voided.FeedbackSamples != initial.FeedbackSamples {
		t.Fatal("void feedback still affected ranking")
	}
	patch = edit(p.ID, p.Version)
	patch["patch"] = map[string]any{"default_occasion": "formal"}
	_ = execute[engine.PreferencesResult](t, s, "preferences_update", patch)
	errorCode(t, s, "wardrobe_suggest", query, "conflict")
}
