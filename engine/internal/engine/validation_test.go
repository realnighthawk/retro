package engine

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestPatchClearsAndRejectsRequiredNull(t *testing.T) {
	g := GarmentData{Name: "Tee", Category: "top", GarmentAttributes: GarmentAttributes{Notes: "old", Brand: "brand"}}
	if e := patchFields(&g, map[string]json.RawMessage{"notes": json.RawMessage(`null`)}, "notes"); e != nil {
		t.Fatal(e)
	}
	if g.Notes != "" || g.Brand != "brand" || g.Name != "Tee" {
		t.Fatalf("patch lost fields: %+v", g)
	}
	if e := patchFields(&g, map[string]json.RawMessage{"name": json.RawMessage(`null`)}, "name"); e == nil {
		t.Fatal("required null accepted")
	}
	if e := patchFields(&g, map[string]json.RawMessage{"owner_id": json.RawMessage(`"other"`)}, "notes"); e == nil {
		t.Fatal("owner patch accepted")
	}
}
func TestOutfitDatesAndSelections(t *testing.T) {
	now := time.Date(2026, 10, 8, 1, 0, 0, 0, time.UTC)
	for _, tc := range []struct {
		day, zone, state string
		valid            bool
	}{{"2026-10-07", "America/Los_Angeles", "worn", true}, {"2026-10-08", "America/Los_Angeles", "worn", false}, {"2026-10-08", "America/Los_Angeles", "planned", true}, {"2026-02-30", "UTC", "planned", false}, {"2026-10-07", "Local", "worn", false}} {
		t.Run(tc.day+tc.zone+tc.state, func(t *testing.T) {
			o := OutfitData{Day: tc.day, TimeZone: tc.zone, State: tc.state}
			if (validateOutfit(&o, now) == nil) != tc.valid {
				t.Fatalf("unexpected validity: %+v", tc)
			}
		})
	}
	key := uuid.NewString()
	if e := validateSelections([]Selection{{key, "base"}, {key, "mid"}}); e == nil {
		t.Fatal("duplicate garment accepted")
	}
}
func TestOperationBoundary(t *testing.T) {
	s := New(nil, nil)
	if len(s.Operations()) != 46 {
		t.Fatalf("operation count: %d", len(s.Operations()))
	}
	op := s.operations["garments_create"]
	for _, raw := range []string{`[]`, `null`, `{"idempotency_key":"x","name":"Tee","category":"top","owner_id":"someone"}`, `{"idempotency_key":"x","name":1,"category":"top"}`, `{"idempotency_key":"x","name":"Tee","category":"top"} {}`} {
		if _, _, e := op.decode([]byte(raw)); e == nil {
			t.Fatalf("accepted %s", raw)
		}
	}
	if _, _, e := op.decode([]byte(`{"idempotency_key":"x","name":"Tee","category":"top"}`)); e != nil {
		t.Fatal(e)
	}
	if _, _, e := s.operations["garments_update"].decode([]byte(`{"idempotency_key":"x","id":"x","expected_version":1,"patch":{"notes":null,"favourite":true}}`)); e != nil {
		t.Fatal(e)
	}
}
func TestCursorBindsFilters(t *testing.T) {
	filters := GarmentListInput{Category: "top"}
	value := cursor(filters, uuid.NewString())
	if _, _, e := page(ListInput{Cursor: *value}, filters); e != nil {
		t.Fatal(e)
	}
	if _, _, e := page(ListInput{Cursor: *value}, GarmentListInput{Category: "bottom"}); e == nil {
		t.Fatal("changed filters accepted")
	}
}
func TestCanonicalInput(t *testing.T) {
	s := New(nil, nil)
	op := s.operations["garments_update"]
	a := []byte(`{"id":"x","expected_version":9007199254740993,"idempotency_key":"k","patch":{"notes":"n","colours":["blue","red"]}}`)
	b := []byte(`{"patch":{"colours":["blue","red"],"notes":"n"},"idempotency_key":"k","expected_version":9007199254740993,"id":"x"}`)
	_, first, e := op.decode(a)
	if e != nil {
		t.Fatal(e)
	}
	_, second, e := op.decode(b)
	if e != nil || string(first) != string(second) {
		t.Fatalf("object order changed canonical input: %v", e)
	}
	var input EditInput
	if e := json.Unmarshal(first, &input); e != nil || input.ExpectedVersion != 9007199254740993 {
		t.Fatal("canonical input changed integer precision")
	}
}
func TestSuggestionsAreDistinctAvailableAndRespectRequired(t *testing.T) {
	g := []Garment{}
	for i := 0; i < 3; i++ {
		g = append(g, Garment{ID: uuid.NewString(), Version: 1, GarmentData: GarmentData{Name: "tee", Category: "top", Availability: "ready"}})
	}
	bottom := Garment{ID: uuid.NewString(), Version: 1, GarmentData: GarmentData{Name: "jeans", Category: "bottom", Availability: "ready"}}
	dirty := Garment{ID: uuid.NewString(), Version: 1, GarmentData: GarmentData{Name: "dirty", Category: "footwear", Availability: "washing"}}
	g = append(g, bottom, dirty)
	in := SuggestInput{Day: "2026-10-08", RequiredIDs: []string{bottom.ID}}
	p := preferenceDefaults()
	options, e := buildSuggestions(g, in, p, nil)
	if e != nil {
		t.Fatal(e)
	}
	if len(options) != 3 {
		t.Fatalf("got %d choices", len(options))
	}
	seen := map[string]bool{}
	for _, o := range options {
		if seen[o.Fingerprint] {
			t.Fatal("repeated outfit")
		}
		seen[o.Fingerprint] = true
		found := false
		for _, v := range o.Items {
			if v.GarmentID == dirty.ID {
				t.Fatal("washing piece suggested")
			}
			if v.GarmentID == bottom.ID {
				found = true
			}
		}
		if !found {
			t.Fatal("required piece lost")
		}
		if len(o.MissingRoles) != 1 || o.MissingRoles[0] != "feet" {
			t.Fatalf("missing roles: %v", o.MissingRoles)
		}
	}
	in.Variant = 1
	alternate, e := buildSuggestions(g, in, p, nil)
	if e != nil || alternate[0].Fingerprint == options[0].Fingerprint {
		t.Fatal("shuffle did not change combination")
	}
	in.RequiredIDs = []string{dirty.ID}
	if _, e = buildSuggestions(g, in, p, nil); e == nil {
		t.Fatal("unavailable required piece silently dropped")
	}
}
