package engine

import (
	"encoding/json"
	"strings"
	"testing"
)

func preferenceDefaults() PreferencesData {
	return PreferencesData{TemperatureUnit: "celsius", TemperatureSensitivity: "normal", ColdThresholdC: 10, HotThresholdC: 25, LayeringPreference: "moderate", AvoidRepeatDays: 7, PreferUnderusedItems: true, Variety: "moderate"}
}

func TestPreferenceValidation(t *testing.T) {
	for _, tc := range []struct {
		name  string
		patch string
	}{
		{"overlapping colours", `{"preferred_colours":[" Blue "],"avoided_colours":["blue"]}`},
		{"duplicate values", `{"preferred_styles":["casual","CASUAL"]}`},
		{"empty value", `{"preferred_colours":[" "]}`},
		{"overlapping thresholds", `{"cold_threshold_c":25,"hot_threshold_c":25}`},
		{"out of range threshold", `{"cold_threshold_c":-21}`},
		{"invalid repeat interval", `{"avoid_repeat_days":31}`},
		{"unsupported enum", `{"layering_preference":"lots"}`},
		{"unknown field", `{"preferred_provider":"cloud"}`},
		{"null repeat interval", `{"avoid_repeat_days":null}`},
		{"null toggle", `{"prefer_underused_items":null}`},
		{"wrong type", `{"preferred_styles":"casual"}`},
		{"fractional interval", `{"avoid_repeat_days":1.5}`},
		{"empty patch", `{}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p := preferenceDefaults()
			var patch map[string]json.RawMessage
			if e := json.Unmarshal([]byte(tc.patch), &patch); e != nil {
				t.Fatal(e)
			}
			if e := patchPreferences(&p, patch); e == nil || PublicError(e).Code != "invalid_input" {
				t.Fatalf("invalid preference patch accepted: %v", e)
			}
		})
	}
	p := preferenceDefaults()
	p.PreferredStyles = []string{strings.Repeat("a", 101)}
	if validatePreferences(&p) == nil {
		t.Fatal("oversized preference value accepted")
	}
	p = preferenceDefaults()
	for i := 0; i < 11; i++ {
		p.PreferredStyles = append(p.PreferredStyles, strings.Repeat("a", i+1))
	}
	if validatePreferences(&p) == nil {
		t.Fatal("oversized preference list accepted")
	}
}

func TestPreferencePatchPreservesUnselectedSettings(t *testing.T) {
	p := preferenceDefaults()
	p.PreferredColours = []string{"blue"}
	p.DefaultOccasion = "work"
	patch := map[string]json.RawMessage{
		"preferred_colours":      json.RawMessage(`null`),
		"default_occasion":       json.RawMessage(`null`),
		"preferred_styles":       json.RawMessage(`[" Casual "]`),
		"avoid_repeat_days":      json.RawMessage(`0`),
		"prefer_underused_items": json.RawMessage(`false`),
	}
	if e := patchPreferences(&p, patch); e != nil {
		t.Fatal(e)
	}
	if p.PreferredColours == nil || len(p.PreferredColours) != 0 || p.AvoidedColours == nil || p.DefaultOccasion != "" || p.PreferredStyles[0] != "Casual" || p.AvoidRepeatDays != 0 || p.PreferUnderusedItems {
		t.Fatalf("cleared or explicit zero/false settings were lost: %+v", p)
	}
	if p.TemperatureUnit != "celsius" || p.ColdThresholdC != 10 || p.HotThresholdC != 25 || p.Variety != "moderate" {
		t.Fatal("patch replaced unselected settings")
	}
}
