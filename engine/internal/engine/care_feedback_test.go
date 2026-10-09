package engine

import (
	"encoding/json"
	"testing"

	"github.com/google/uuid"
)

func TestConfirmedCareAndUnknownFields(t *testing.T) {
	temp := 30
	valid := CareSettings{WashMethod: "machine", MaxTempC: &temp, Cycle: "gentle", Confirmed: true}
	if e := validateCare(&valid); e != nil {
		t.Fatal(e)
	}
	for _, care := range []CareSettings{
		{Confirmed: true},
		{WashMethod: "machine", Cycle: "normal", Confirmed: true},
		{WashMethod: "dry_clean", MaxTempC: &temp},
		{Source: "label", WashMethod: "hand"},
	} {
		if e := validateCare(&care); e == nil {
			t.Fatalf("accepted unsafe care: %+v", care)
		}
	}
	var data GarmentAttributes
	if e := patchFields(&data, map[string]json.RawMessage{"care": json.RawMessage(`{"wash_method":"machine","guessed":true}`)}, "care"); e == nil {
		t.Fatal("unknown nested field accepted")
	}
	data.Care = &valid
	if e := patchFields(&data, map[string]json.RawMessage{"care": json.RawMessage(`null`)}, "care"); e != nil || data.Care != nil {
		t.Fatal("care reset failed", e)
	}
}

func TestMachinePresetsAndFeedbackReset(t *testing.T) {
	p := PreferencesData{MachinePresets: []MachinePreset{{ID: uuid.NewString(), Name: " Cold wash ", TemperatureC: 0, Cycle: "gentle"}}}
	if e := validatePresets(&p); e != nil || p.MachinePresets[0].Name != "Cold wash" {
		t.Fatal("valid cold preset rejected", e)
	}
	p.MachinePresets = append(p.MachinePresets, p.MachinePresets[0])
	if validatePresets(&p) == nil {
		t.Fatal("duplicate preset identity accepted")
	}
	one, zero := 1, 0
	f := FeedbackData{Rating: &one, Warmth: "too_cold", Comment: "test"}
	if validateFeedback(&f) != nil {
		t.Fatal("valid feedback rejected")
	}
	if e := patchFields(&f, map[string]json.RawMessage{"rating": json.RawMessage(`null`), "warmth": json.RawMessage(`null`), "comment": json.RawMessage(`null`)}, "rating", "warmth", "comment"); e != nil {
		t.Fatal(e)
	}
	if e := validateFeedback(&f); e != nil || f.Rating != nil || f.Comment != "" || f.Warmth != "unknown" {
		t.Fatal("explicit reset failed", e)
	}
	f.Rating = &zero
	if validateFeedback(&f) == nil {
		t.Fatal("zero rating accepted")
	}
}
