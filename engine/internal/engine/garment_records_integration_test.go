package engine_test

import (
	"github.com/google/uuid"
	"github.com/nighthawklabs/retro/engine/internal/engine"
	"strings"
	"testing"
	"time"
)

// P4.1: richer garment records keep omission, explicit clearing, money exactness and historical snapshots apart.
func TestIntegrationGarmentRecordsAndPurchase(t *testing.T) {
	s := integrationService(t, nil)
	body := map[string]any{"idempotency_key": uuid.NewString(), "id": uuid.NewString(), "name": "Field jacket " + uuid.NewString(), "category": "outerwear",
		"pattern": "herringbone", "style": "field jacket", "fit": "relaxed",
		"purchase": map[string]any{"date": "2026-03-02", "currency": "usd", "amount": "199.9", "source": "receipt", "evidence": "Receipt 2026-03-02 treated as a proposal, not proof"}}
	garment := execute[engine.GarmentResult](t, s, "garments_create", body).Garment
	purchase := garment.Purchase
	if purchase == nil || purchase.AmountMinor == nil || *purchase.AmountMinor != 19990 || purchase.Currency != "USD" ||
		purchase.CurrencyExponent == nil || *purchase.CurrencyExponent != 2 || purchase.Amount != "" || purchase.Source != "receipt" {
		t.Fatalf("purchase round trip: %+v", purchase)
	}
	replayed := execute[engine.GarmentResult](t, s, "garments_create", body).Garment
	if replayed.Version != garment.Version || replayed.Purchase == nil || *replayed.Purchase.AmountMinor != 19990 {
		t.Fatalf("replay changed the record: %+v", replayed)
	}
	patch := edit(garment.ID, garment.Version)
	patch["patch"] = map[string]any{"notes": "kept"}
	garment = execute[engine.GarmentResult](t, s, "garments_update", patch).Garment
	if garment.Pattern != "herringbone" || garment.Fit != "relaxed" || garment.Purchase == nil || *garment.Purchase.AmountMinor != 19990 {
		t.Fatalf("omission cleared fields: %+v", garment)
	}
	day := time.Now().UTC().Format("2006-01-02")
	worn := execute[engine.OutfitResult](t, s, "outfits_create", map[string]any{"idempotency_key": uuid.NewString(), "day": day, "time_zone": "UTC",
		"state": "worn", "items": []engine.Selection{{GarmentID: garment.ID, Role: "outer"}}}).Outfit
	patch = edit(garment.ID, garment.Version)
	patch["patch"] = map[string]any{"pattern": "twill", "purchase": nil, "style": "changed"}
	garment = execute[engine.GarmentResult](t, s, "garments_update", patch).Garment
	if garment.Purchase != nil || garment.Pattern != "twill" {
		t.Fatalf("explicit clearing failed: %+v", garment.Purchase)
	}
	patch = edit(garment.ID, garment.Version)
	patch["patch"] = map[string]any{"purchase": map[string]any{"currency": "JPY", "amount": "12000"}}
	garment = execute[engine.GarmentResult](t, s, "garments_update", patch).Garment
	if garment.Purchase == nil || *garment.Purchase.AmountMinor != 12000 || *garment.Purchase.CurrencyExponent != 0 || garment.Purchase.Date != "" {
		t.Fatalf("partial purchase record: %+v", garment.Purchase)
	}
	patch = edit(garment.ID, garment.Version)
	patch["patch"] = map[string]any{"purchase": map[string]any{"currency": "USD", "amount": "10.505"}}
	errorCode(t, s, "garments_update", patch, "invalid_input")
	patch = edit(garment.ID, garment.Version)
	patch["patch"] = map[string]any{"purchase": map[string]any{"amount": "10.00"}}
	errorCode(t, s, "garments_update", patch, "invalid_input")
	patch = edit(garment.ID, garment.Version)
	patch["patch"] = map[string]any{"purchase": map[string]any{"amount_minor": 0, "currency": "USD", "source": "manual"}}
	garment = execute[engine.GarmentResult](t, s, "garments_update", patch).Garment
	if garment.Purchase == nil || *garment.Purchase.AmountMinor != 0 {
		t.Fatal("a recorded zero amount was treated as unknown")
	}
	historical := execute[engine.OutfitResult](t, s, "outfits_get", map[string]any{"id": worn.ID}).Outfit
	snapshot := historical.Items[0].Snapshot
	if snapshot == nil || snapshot.Purchase == nil || *snapshot.Purchase.AmountMinor != 19990 || snapshot.Pattern != "herringbone" {
		t.Fatalf("historical snapshot followed later edits: %+v", snapshot)
	}
	history := execute[engine.Page[engine.Change]](t, s, "history_list", map[string]any{"entity_type": "garment", "id": garment.ID})
	var audited bool
	for _, change := range history.Items {
		if strings.Contains(string(change.Before), "herringbone") && strings.Contains(string(change.After), "twill") {
			audited = true
		}
	}
	if !audited {
		t.Fatalf("purchase/pattern changes missing from audit: %d entries", len(history.Items))
	}
}
