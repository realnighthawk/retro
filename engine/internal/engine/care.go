package engine

import "strings"

type CareSettings struct {
	WashMethod  string `json:"wash_method"`
	MaxTempC    *int   `json:"max_temp_c,omitempty"`
	Cycle       string `json:"cycle"`
	ColourGroup string `json:"colour_group"`
	Drying      string `json:"drying"`
	Source      string `json:"source"`
	Evidence    string `json:"evidence,omitempty"`
	Confirmed   bool   `json:"confirmed"`
}

type MachinePreset struct {
	ID           string `json:"id"`
	Name         string `json:"name"`
	TemperatureC int    `json:"temperature_c"`
	Cycle        string `json:"cycle"`
	Drying       string `json:"drying"`
}

func validateCare(c *CareSettings) error {
	if c == nil {
		return nil
	}
	if c.WashMethod == "" {
		c.WashMethod = "unknown"
	}
	if c.Cycle == "" {
		c.Cycle = "unknown"
	}
	if c.ColourGroup == "" {
		c.ColourGroup = "unknown"
	}
	if c.Drying == "" {
		c.Drying = "unknown"
	}
	if c.Source == "" {
		c.Source = "manual"
	}
	c.Evidence = strings.TrimSpace(c.Evidence)
	if !oneOf(c.WashMethod, "unknown", "machine", "hand", "dry_clean", "do_not_wash") ||
		!oneOf(c.Cycle, "unknown", "normal", "gentle", "delicate") ||
		!oneOf(c.ColourGroup, "unknown", "white", "light", "dark", "separate") ||
		!oneOf(c.Drying, "unknown", "line", "flat", "tumble_low", "tumble_normal", "do_not_tumble", "professional") ||
		!oneOf(c.Source, "manual", "label") {
		return invalid("unsupported care setting")
	}
	if c.MaxTempC != nil && (*c.MaxTempC < 0 || *c.MaxTempC > 95) {
		return invalid("care temperature must be between 0 and 95 Celsius")
	}
	if len(c.Evidence) > 2000 || c.Source == "label" && c.Evidence == "" {
		return invalid("label care requires bounded readable evidence")
	}
	if oneOf(c.WashMethod, "dry_clean", "do_not_wash") && (c.MaxTempC != nil || c.Cycle != "unknown") {
		return invalid("non-wash care cannot specify wash temperature or cycle")
	}
	if c.Confirmed && (c.WashMethod == "unknown" || oneOf(c.WashMethod, "machine", "hand") && c.MaxTempC == nil || c.WashMethod == "machine" && c.Cycle == "unknown") {
		return invalid("confirm the wash method, temperature and machine cycle before confirming care")
	}
	return nil
}

func validatePresets(p *PreferencesData) error {
	if p.MachinePresets == nil {
		p.MachinePresets = []MachinePreset{}
	}
	if len(p.MachinePresets) > 10 {
		return invalid("machine presets cannot exceed 10 entries")
	}
	seen := map[string]bool{}
	for i := range p.MachinePresets {
		v := &p.MachinePresets[i]
		key, e := id(v.ID)
		if e != nil {
			return e
		}
		v.ID = key
		v.Name = strings.TrimSpace(v.Name)
		if seen[key] || v.Name == "" || len(v.Name) > 100 {
			return invalid("machine presets require unique IDs and bounded names")
		}
		seen[key] = true
		if v.Drying == "" {
			v.Drying = "unknown"
		}
		if v.TemperatureC < 0 || v.TemperatureC > 95 || !oneOf(v.Cycle, "normal", "gentle", "delicate") || !oneOf(v.Drying, "unknown", "line", "flat", "tumble_low", "tumble_normal", "do_not_tumble", "professional") {
			return invalid("unsupported machine preset")
		}
	}
	return nil
}
