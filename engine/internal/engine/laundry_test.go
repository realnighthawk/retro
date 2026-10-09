package engine

import "testing"

func TestLaundryChecksEveryConfirmedRestriction(t *testing.T) {
	temp := 20
	p := LaundryProgram{WashMethod: "machine", TemperatureC: &temp, Cycle: "gentle", Drying: "line"}
	g := Garment{ID: "11111111-1111-4111-8111-111111111111", GarmentData: GarmentData{Availability: "needs_wash", GarmentAttributes: GarmentAttributes{Care: &CareSettings{WashMethod: "machine", MaxTempC: &temp, Cycle: "gentle", ColourGroup: "dark", Drying: "line", Confirmed: true}}}}
	if e := validateLaundryProgram(p); e != nil || laundryRestriction(g, p) != "" {
		t.Fatal("valid cold load rejected")
	}
	for _, change := range []func(*CareSettings){
		func(c *CareSettings) { c.Confirmed = false }, func(c *CareSettings) { c.WashMethod = "hand" },
		func(c *CareSettings) { c.MaxTempC = nil }, func(c *CareSettings) { limit := 0; c.MaxTempC = &limit },
		func(c *CareSettings) { c.Cycle = "delicate" }, func(c *CareSettings) { c.ColourGroup = "unknown" },
		func(c *CareSettings) { c.Drying = "flat" }, func(c *CareSettings) { c.Drying = "unknown" },
	} {
		copy := *g.Care
		change(&copy)
		candidate := g
		candidate.Care = &copy
		if laundryRestriction(candidate, p) == "" {
			t.Fatal("unknown or incompatible care entered a load")
		}
	}
	g.Care.Drying = "do_not_tumble"
	if laundryRestriction(g, p) != "" {
		t.Fatal("air drying violated do-not-tumble restriction")
	}
	p.Drying = "tumble_low"
	if laundryRestriction(g, p) == "" {
		t.Fatal("do-not-tumble accepted a dryer")
	}
	g.Care.ColourGroup = "separate"
	if laundryGroup(g) != "separate:"+g.ID {
		t.Fatal("wash-separately did not get an individual group")
	}
	zero := 0
	p.TemperatureC = &zero
	p.Drying = "line"
	if e := validateLaundryProgram(p); e != nil {
		t.Fatal("explicit zero temperature treated as missing")
	}
	p.TemperatureC = nil
	if validateLaundryProgram(p) == nil {
		t.Fatal("missing temperature accepted")
	}
	if validateLaundryProgram(LaundryProgram{WashMethod: "dry_clean", Cycle: "unknown", Drying: "professional"}) != nil {
		t.Fatal("professional care rejected")
	}
	if validateLaundryProgram(LaundryProgram{WashMethod: "hand", TemperatureC: &temp, Cycle: "normal", Drying: "line"}) == nil {
		t.Fatal("hand wash invented a machine cycle")
	}
}
