package engine_test

import (
	"github.com/google/uuid"
	"github.com/nighthawklabs/retro/engine/internal/engine"
	"testing"
)

// P4.3: ranked usage, never-worn versus not-worn-in-range, distributions, trends and separate
// feedback/selection accounting are checked against real records in a date range no other test uses.
func TestIntegrationWardrobeAnalytics(t *testing.T) {
	s := integrationService(t, nil)
	key := uuid.NewString()
	create := func(name string, fields map[string]any) engine.Garment {
		body := map[string]any{"idempotency_key": uuid.NewString(), "name": name + " " + key, "category": "top"}
		for k, v := range fields {
			body[k] = v
		}
		return execute[engine.GarmentResult](t, s, "garments_create", body).Garment
	}
	plan := func(day string, state string, garment engine.Garment) engine.Outfit {
		return execute[engine.OutfitResult](t, s, "outfits_create", map[string]any{"idempotency_key": uuid.NewString(), "day": day, "time_zone": "UTC",
			"state": state, "items": []engine.Selection{{GarmentID: garment.ID, Role: "base"}}}).Outfit
	}
	selectDay := func(day string, outfit *engine.Outfit, version int64) engine.DaySelectionResult {
		body := map[string]any{"idempotency_key": uuid.NewString(), "id": uuid.NewSHA1(uuid.NameSpaceOID, []byte("retro-day-selection:"+day)).String(),
			"day": day, "expected_version": version}
		if outfit != nil {
			body["outfit_id"] = outfit.ID
			body["expected_outfit_version"] = outfit.Version
		}
		return execute[engine.DaySelectionResult](t, s, "wardrobe_day_selection_update", body)
	}
	usage := func(id string, list []engine.GarmentUsage) *engine.GarmentUsage {
		for i := range list {
			if list[i].GarmentID == id {
				return &list[i]
			}
		}
		return nil
	}
	unworn := func(id string, list []engine.UnwornGarment) *engine.UnwornGarment {
		for i := range list {
			if list[i].GarmentID == id {
				return &list[i]
			}
		}
		return nil
	}
	anorak := create("Anorak", map[string]any{"colours": []string{"Blue"}, "purchase": map[string]any{"currency": "USD", "amount": "30.00", "source": "manual"}})
	blazer := create("Blazer", map[string]any{"colours": []string{"blue", "red"}})
	cardigan := create("Cardigan", map[string]any{"colours": []string{"red"}})
	dress := create("Dress", map[string]any{"colours": []string{"green"}})
	boots := create("Boots", map[string]any{"category": "footwear", "colours": []string{"black"}, "purchase": map[string]any{"currency": "EUR", "amount": "10.00", "source": "manual"}})
	selected := plan("1999-03-01", "planned", anorak)
	selectDay("1999-03-01", &selected, 0)
	selected = execute[engine.OutfitResult](t, s, "outfits_confirm", edit(selected.ID, selected.Version)).Outfit
	plan("1999-03-02", "worn", anorak)
	plan("1999-03-03", "worn", anorak)
	plan("1999-03-01", "worn", cardigan)
	plan("1999-03-02", "worn", boots)
	plan("1999-03-04", "planned", blazer)
	cleared := plan("1999-03-05", "planned", anorak)
	selectDay("1999-03-05", &cleared, 0)
	selectDay("1999-03-05", nil, 1)
	plan("1999-02-20", "worn", dress)
	feedbackID := uuid.NewSHA1(uuid.NameSpaceOID, []byte("retro-feedback:"+selected.ID)).String()
	execute[engine.FeedbackResult](t, s, "outfits_feedback_update", map[string]any{"idempotency_key": uuid.NewString(), "id": feedbackID,
		"expected_version": 0, "outfit_id": selected.ID, "expected_outfit_version": selected.Version, "patch": map[string]any{"rating": 5}})

	review := execute[engine.Analysis](t, s, "wardrobe_analyze", map[string]any{"from": "1999-03-01", "to": "1999-03-07"})
	if review.OutfitEvents != 4 || review.WearDays != 3 {
		t.Fatalf("range counts: %d events on %d days", review.OutfitEvents, review.WearDays)
	}
	var categoryGarments, categoryUnworn int64
	for _, c := range review.Categories {
		categoryGarments += c.Garments
		categoryUnworn += c.Garments - c.WornGarments
	}
	if categoryGarments != review.Garments || categoryUnworn != review.UnwornGarments || review.NotWornInRangeTotal != review.UnwornGarments {
		t.Fatalf("counts disagree: garments %d/%d unworn %d/%d list %d", categoryGarments, review.Garments, categoryUnworn, review.UnwornGarments, review.NotWornInRangeTotal)
	}
	top := usage(anorak.ID, review.MostWorn)
	if top == nil || top.WearEvents != 3 || top.WearDays != 3 || top.CostPerWear == nil || top.CostPerWear.AmountMinor != 1000 ||
		top.CostPerWear.Currency != "USD" || top.CostPerWear.WearEvents != 3 || top.CostPerWear.CurrencyExponent != 2 {
		t.Fatalf("most worn: %+v", top)
	}
	if len(review.MostWorn) != 3 || len(review.LeastWorn) != 3 || review.RankedLimit != 20 {
		t.Fatalf("ranked lists: %d most, %d least", len(review.MostWorn), len(review.LeastWorn))
	}
	quiet := usage(cardigan.ID, review.LeastWorn)
	if quiet == nil || quiet.WearEvents != 1 || quiet.CostPerWear != nil {
		t.Fatalf("least worn without a recorded price: %+v", quiet)
	}
	euros := usage(boots.ID, review.MostWorn)
	if euros == nil || euros.CostPerWear == nil || euros.CostPerWear.AmountMinor != 500 || euros.CostPerWear.Currency != "EUR" {
		t.Fatalf("cost per wear keeps its own currency: %+v", euros)
	}
	if usage(dress.ID, review.MostWorn) != nil {
		t.Fatal("an out-of-range wear entered the ranked list")
	}
	if absent := usage(blazer.ID, review.MostWorn); absent != nil {
		t.Fatal("a planned garment counted as worn")
	}
	// The lists are capped and ordered oldest first, so membership is only asserted while this
	// shared test database holds fewer unworn garments than the cap. The totals are always exact.
	if review.NeverWornTotal > int64(len(review.NeverWorn)) || review.NotWornInRangeTotal > int64(len(review.NotWornInRange)) {
		t.Fatalf("capped unworn lists must report their full totals: %d/%d %d/%d", len(review.NeverWorn), review.NeverWornTotal, len(review.NotWornInRange), review.NotWornInRangeTotal)
	}
	never := unworn(blazer.ID, review.NeverWorn)
	if never == nil || never.LastWornOn != nil || never.WearEvents != 0 {
		t.Fatalf("never worn: %+v", never)
	}
	earlier := unworn(dress.ID, review.NotWornInRange)
	if earlier == nil || earlier.LastWornOn == nil || *earlier.LastWornOn != "1999-02-20" || earlier.WearEvents != 1 {
		t.Fatalf("not worn in range: %+v", earlier)
	}
	if unworn(dress.ID, review.NeverWorn) != nil {
		t.Fatal("a garment worn before the range was reported as never worn")
	}
	if review.NeverWornTotal < 1 || review.NeverWornTotal >= review.NotWornInRangeTotal {
		t.Fatalf("never worn is not a strict subset of not worn in range: %d of %d", review.NeverWornTotal, review.NotWornInRangeTotal)
	}
	colour := map[string]engine.ColourUsage{}
	for _, c := range review.Colours {
		colour[c.Colour] = c
	}
	if colour["blue"].WearEvents != 3 || colour["blue"].Garments < 2 || colour["red"].WearEvents != 1 || colour["green"].WearEvents != 0 {
		t.Fatalf("colour distribution: %+v", review.Colours)
	}
	if len(review.Weeks) != 1 || review.Weeks[0].WeekStart != "1999-03-01" || review.Weeks[0].WearEvents != 4 || review.Weeks[0].WearDays != 3 || review.WeeksTruncated {
		t.Fatalf("weekly trend: %+v", review.Weeks)
	}
	if review.Feedback.Records != 1 || review.Feedback.Rated != 1 || len(review.Feedback.Ratings) != 1 || review.Feedback.Ratings[0].Rating != 5 || review.Feedback.Ratings[0].Feedback != 1 {
		t.Fatalf("feedback summary: %+v", review.Feedback)
	}
	if review.Selections.SelectedDays != 1 || review.Selections.ConfirmedDays != 1 || review.Selections.ClearedDays != 1 || review.Selections.PlannedOutfits != 2 {
		t.Fatalf("selection summary: %+v", review.Selections)
	}
	void := execute[engine.OutfitResult](t, s, "outfits_void", edit(selected.ID, selected.Version)).Outfit
	corrected := execute[engine.Analysis](t, s, "wardrobe_analyze", map[string]any{"from": "1999-03-01", "to": "1999-03-07"})
	correctedTop := usage(anorak.ID, corrected.MostWorn)
	if corrected.OutfitEvents != 3 || corrected.WearDays != 2 || correctedTop == nil || correctedTop.WearEvents != 2 ||
		correctedTop.CostPerWear == nil || correctedTop.CostPerWear.AmountMinor != 1500 || correctedTop.CostPerWear.WearEvents != 2 || corrected.Selections.ConfirmedDays != 0 {
		t.Fatalf("void did not correct every count: %+v", correctedTop)
	}
	_ = execute[engine.OutfitResult](t, s, "outfits_restore", edit(void.ID, void.Version))
	restored := execute[engine.Analysis](t, s, "wardrobe_analyze", map[string]any{"from": "1999-03-01", "to": "1999-03-07"})
	restoredTop := usage(anorak.ID, restored.MostWorn)
	if restored.OutfitEvents != 4 || restoredTop == nil || restoredTop.CostPerWear == nil || restoredTop.CostPerWear.AmountMinor != 1000 {
		t.Fatal("restoring a wear did not restore its counts")
	}
	boundary := execute[engine.Analysis](t, s, "wardrobe_analyze", map[string]any{"from": "1999-03-02", "to": "1999-03-03"})
	boundaryTop := usage(anorak.ID, boundary.MostWorn)
	if boundary.OutfitEvents != 3 || boundary.WearDays != 2 || boundaryTop == nil || boundaryTop.WearEvents != 2 {
		t.Fatalf("date boundaries: %d events on %d days", boundary.OutfitEvents, boundary.WearDays)
	}
	archived := execute[engine.GarmentResult](t, s, "garments_archive", edit(blazer.ID, blazer.Version)).Garment
	afterArchive := execute[engine.Analysis](t, s, "wardrobe_analyze", map[string]any{"from": "1999-03-01", "to": "1999-03-07"})
	if entry := unworn(archived.ID, afterArchive.NeverWorn); afterArchive.NeverWornTotal > int64(len(afterArchive.NeverWorn)) {
		t.Fatal("the archived review lost its never-worn total")
	} else if entry == nil || !entry.Archived {
		t.Fatalf("archived history stays visible and labelled: %+v", entry)
	}
	whole := execute[engine.Analysis](t, s, "wardrobe_analyze", map[string]any{})
	if len(whole.Weeks) == 0 || whole.Weeks[0].WeekStart <= "1999-03-01" || !whole.WeeksTruncated {
		t.Fatalf("an unbounded review keeps its most recent bounded weeks: %d weeks truncated=%v from %s", len(whole.Weeks), whole.WeeksTruncated, whole.Weeks[0].WeekStart)
	}
	errorCode(t, s, "wardrobe_analyze", map[string]any{"from": "1999-03-07", "to": "1999-03-01"}, "invalid_input")
}
