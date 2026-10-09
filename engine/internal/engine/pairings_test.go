package engine

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/google/uuid"
)

func TestPairingValidationKeepsManualRolesAndRejectsInvalidPieces(t *testing.T) {
	a, b := uuid.NewString(), uuid.NewString()
	valid := PairingData{Name: "  Work combination  ", Items: []Selection{{a, "accessory"}, {b, "accessory"}}}
	if e := validatePairing(&valid); e != nil || valid.Name != "Work combination" {
		t.Fatalf("manual pairing failed: %+v %v", valid, e)
	}
	for _, p := range []PairingData{
		{Name: "", Items: valid.Items},
		{Name: strings.Repeat("a", 101), Items: valid.Items},
		{Name: "One piece", Items: valid.Items[:1]},
		{Name: "Duplicate", Items: []Selection{{a, "base"}, {strings.ToUpper(a), "mid"}}},
		{Name: "Unknown", Items: []Selection{{a, "fake"}, {b, "feet"}}},
		{Name: "Too long", Notes: strings.Repeat("n", 4001), Items: valid.Items},
	} {
		if e := validatePairing(&p); e == nil {
			t.Fatalf("accepted invalid pairing: %+v", p)
		}
	}
}
func TestDailyIdentityAndOperationBoundaryPreserveExactVersions(t *testing.T) {
	if daySelectionID("2026-10-09") != "369214c9-e940-5410-98f9-43a71b77fe61" || daySelectionID("2026-10-09") == daySelectionID("2026-10-10") {
		t.Fatal("daily identity is unstable or crosses dates")
	}
	s := New(nil, nil)
	op := s.operations["wardrobe_day_selection_update"]
	_, body, e := op.decode([]byte(`{"idempotency_key":"request","id":"11111111-1111-4111-8111-111111111111","day":"2026-10-09","expected_version":9007199254740993,"outfit_id":"22222222-2222-4222-8222-222222222222","expected_outfit_version":9007199254740993}`))
	var in DaySelectionInput
	if e != nil || json.Unmarshal(body, &in) != nil || in.ExpectedVersion != 9007199254740993 || in.ExpectedOutfitVersion == nil || *in.ExpectedOutfitVersion != 9007199254740993 {
		t.Fatal("selection versions lost precision")
	}
	for _, name := range []string{"pairings_get", "pairings_list", "wardrobe_day_get"} {
		if s.operations[name].Write {
			t.Fatalf("%s unexpectedly writes", name)
		}
	}
}
