package engine

import (
	"bytes"
	"context"
	"encoding/json"
	"strings"
	"time"
)

// Every engine serves one wardrobe; this identity is stable across clients and retries.
const PreferencesID = "971d5190-0ce2-4aaf-aa0a-753c3dde8fc9"

type PreferencesData struct {
	PreferredColours       []string        `json:"preferred_colours"`
	AvoidedColours         []string        `json:"avoided_colours"`
	PreferredStyles        []string        `json:"preferred_styles"`
	DefaultOccasion        string          `json:"default_occasion"`
	TemperatureUnit        string          `json:"temperature_unit"`
	TemperatureSensitivity string          `json:"temperature_sensitivity"`
	ColdThresholdC         int             `json:"cold_threshold_c"`
	HotThresholdC          int             `json:"hot_threshold_c"`
	LayeringPreference     string          `json:"layering_preference"`
	AvoidRepeatDays        int             `json:"avoid_repeat_days"`
	PreferUnderusedItems   bool            `json:"prefer_underused_items"`
	Variety                string          `json:"variety"`
	MachinePresets         []MachinePreset `json:"machine_presets"`
}

type Preferences struct {
	PreferencesData
	ID        string    `json:"id"`
	Version   int64     `json:"version"`
	UpdatedAt time.Time `json:"updated_at"`
}

type PreferencesResult struct {
	Preferences Preferences `json:"preferences"`
}

func (u *unit) getPreferences(ctx context.Context) (Preferences, error) {
	var p Preferences
	var attrs []byte
	if e := u.tx.QueryRow(ctx, `SELECT id::text,version,attributes,updated_at FROM retro.preferences WHERE id=$1`, PreferencesID).Scan(&p.ID, &p.Version, &attrs, &p.UpdatedAt); e != nil {
		return p, e
	}
	e := json.Unmarshal(attrs, &p.PreferencesData)
	if p.MachinePresets == nil {
		p.MachinePresets = []MachinePreset{}
	}
	return p, e
}

func validatePreferences(p *PreferencesData) error {
	if e := validatePresets(p); e != nil {
		return e
	}
	for _, list := range []*[]string{&p.PreferredColours, &p.AvoidedColours, &p.PreferredStyles} {
		if len(*list) > 10 {
			return invalid("preference lists cannot exceed 10 entries")
		}
		seen := map[string]bool{}
		for i, value := range *list {
			value = strings.TrimSpace(value)
			key := strings.ToLower(value)
			if value == "" || len(value) > 100 || seen[key] {
				return invalid("preference lists require unique nonempty values of at most 100 bytes")
			}
			seen[key] = true
			(*list)[i] = value
		}
		if *list == nil {
			*list = []string{}
		}
	}
	for _, preferred := range p.PreferredColours {
		for _, avoided := range p.AvoidedColours {
			if strings.EqualFold(preferred, avoided) {
				return invalid("a colour cannot be both preferred and avoided")
			}
		}
	}
	p.DefaultOccasion = strings.TrimSpace(p.DefaultOccasion)
	if len(p.DefaultOccasion) > 100 {
		return invalid("default_occasion exceeds 100 bytes")
	}
	if !oneOf(p.TemperatureUnit, "celsius", "fahrenheit") ||
		!oneOf(p.TemperatureSensitivity, "low", "normal", "high") ||
		!oneOf(p.LayeringPreference, "minimal", "moderate", "heavy") ||
		!oneOf(p.Variety, "low", "moderate", "high") {
		return invalid("unsupported preference setting")
	}
	if p.ColdThresholdC < -20 || p.ColdThresholdC > 30 || p.HotThresholdC < 10 || p.HotThresholdC > 45 || p.ColdThresholdC >= p.HotThresholdC {
		return invalid("temperature thresholds are out of range or overlap")
	}
	if p.AvoidRepeatDays < 0 || p.AvoidRepeatDays > 30 {
		return invalid("avoid_repeat_days must be between 0 and 30")
	}
	return nil
}

func patchPreferences(data *PreferencesData, patch map[string]json.RawMessage) error {
	for key, value := range patch {
		if bytes.Equal(bytes.TrimSpace(value), []byte("null")) && !oneOf(key, "preferred_colours", "avoided_colours", "preferred_styles", "default_occasion", "machine_presets") {
			return invalid("preference setting cannot be null: " + key)
		}
	}
	if e := patchFields(data, patch, "preferred_colours", "avoided_colours", "preferred_styles", "default_occasion", "temperature_unit", "temperature_sensitivity", "cold_threshold_c", "hot_threshold_c", "layering_preference", "avoid_repeat_days", "prefer_underused_items", "variety", "machine_presets"); e != nil {
		return e
	}
	return validatePreferences(data)
}

func updatePreferences(ctx context.Context, u *unit, in PatchInput) (PreferencesResult, error) {
	var result PreferencesResult
	key, e := id(in.ID)
	if e != nil {
		return result, e
	}
	if key != PreferencesID {
		return result, notFound()
	}
	before, e := u.getPreferences(ctx)
	if e != nil {
		return result, e
	}
	if e = version(in.ExpectedVersion, before.Version); e != nil {
		return result, e
	}
	data := before.PreferencesData
	if e = patchPreferences(&data, in.Patch); e != nil {
		return result, e
	}
	attrs, e := json.Marshal(data)
	if e != nil {
		return result, e
	}
	if _, e = u.tx.Exec(ctx, `UPDATE retro.preferences SET attributes=$2,version=version+1,updated_at=now() WHERE id=$1`, key, attrs); e != nil {
		return result, e
	}
	result.Preferences, e = u.getPreferences(ctx)
	if e != nil {
		return result, e
	}
	return result, u.audit(ctx, "preferences", key, before, result.Preferences)
}
