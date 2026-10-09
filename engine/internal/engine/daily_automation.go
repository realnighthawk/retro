package engine

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"
	_ "time/tzdata"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const DailySettingsID = "8fe141a8-c2af-435c-9e94-166b53fa4b1a"

type DailySettingsData struct {
	Enabled        bool   `json:"enabled"`
	Mode           string `json:"mode"`
	Hour           int    `json:"hour"`
	Minute         int    `json:"minute"`
	TimeZone       string `json:"time_zone"`
	DeliveryTarget string `json:"delivery_target"`
}
type DailySettings struct {
	DailySettingsData
	ID        string    `json:"id"`
	Version   int64     `json:"version"`
	UpdatedAt time.Time `json:"updated_at"`
}
type DailySettingsResult struct {
	Settings DailySettings `json:"settings"`
}
type DailyReadInput struct {
	Day      string `json:"day"`
	TimeZone string `json:"time_zone"`
}
type DailyGenerateInput struct {
	Meta
	ExpectedSettingsVersion int64 `json:"expected_settings_version"`
}
type DailyDelivery struct {
	ClaimID   string    `json:"claim_id"`
	Status    string    `json:"status"`
	Target    string    `json:"target"`
	Receipt   string    `json:"receipt"`
	Source    string    `json:"source"`
	UpdatedAt time.Time `json:"updated_at"`
}
type DailyRun struct {
	ID              string         `json:"id"`
	Day             string         `json:"day"`
	TimeZone        string         `json:"time_zone"`
	SettingsVersion int64          `json:"settings_version"`
	ExpiresAt       time.Time      `json:"expires_at"`
	Query           SuggestInput   `json:"query"`
	Suggestions     Suggestions    `json:"suggestions"`
	Delivery        *DailyDelivery `json:"delivery"`
}
type DailyRunResult struct {
	Run *DailyRun `json:"run"`
}
type DailyClaimInput struct {
	Meta
	RunID   string `json:"run_id"`
	ClaimID string `json:"claim_id"`
}
type DailyClaimResult struct {
	Run         DailyRun `json:"run"`
	SendAllowed bool     `json:"send_allowed"`
}
type DailyCompleteInput struct {
	DailyClaimInput
	Receipt string `json:"receipt"`
	Source  string `json:"source"`
}

func validateDailySettings(s *DailySettingsData) error {
	s.DeliveryTarget = strings.TrimSpace(s.DeliveryTarget)
	if !oneOf(s.Mode, "morning", "previous_evening") || s.Hour < 0 || s.Hour > 23 || s.Minute < 0 || s.Minute > 59 || len(s.TimeZone) > 100 || len(s.DeliveryTarget) > 200 {
		return invalid("Review the daily cadence, time zone and delivery target")
	}
	if _, e := time.LoadLocation(s.TimeZone); e != nil || s.TimeZone == "" || s.TimeZone == "Local" {
		return invalid("daily time_zone must be an IANA zone")
	}
	return nil
}
func (u *unit) getDailySettings(ctx context.Context) (DailySettings, error) {
	var s DailySettings
	var raw []byte
	e := u.tx.QueryRow(ctx, "SELECT id::text,version,attributes,updated_at FROM retro.daily_settings WHERE id=$1", DailySettingsID).Scan(&s.ID, &s.Version, &raw, &s.UpdatedAt)
	if e == nil {
		e = json.Unmarshal(raw, &s.DailySettingsData)
	}
	return s, e
}
func updateDailySettings(ctx context.Context, u *unit, in PatchInput) (DailySettingsResult, error) {
	var result DailySettingsResult
	key, e := id(in.ID)
	if e != nil {
		return result, e
	}
	if key != DailySettingsID {
		return result, notFound()
	}
	before, e := u.getDailySettings(ctx)
	if e != nil {
		return result, e
	}
	if e = version(in.ExpectedVersion, before.Version); e != nil {
		return result, e
	}
	for _, v := range in.Patch {
		if strings.TrimSpace(string(v)) == "null" {
			return result, invalid("daily settings cannot be null; use an empty delivery_target for generation only")
		}
	}
	data := before.DailySettingsData
	if e = patchFields(&data, in.Patch, "enabled", "mode", "hour", "minute", "time_zone", "delivery_target"); e != nil {
		return result, e
	}
	if e = validateDailySettings(&data); e != nil {
		return result, e
	}
	raw, e := json.Marshal(data)
	if e != nil {
		return result, e
	}
	if _, e = u.tx.Exec(ctx, "UPDATE retro.daily_settings SET attributes=$2,version=version+1,updated_at=now() WHERE id=$1", key, raw); e != nil {
		return result, e
	}
	result.Settings, e = u.getDailySettings(ctx)
	if e != nil {
		return result, e
	}
	return result, u.audit(ctx, "daily_settings", key, before, result.Settings)
}
func dailyRunID(day, zone string) string {
	return uuid.NewSHA1(uuid.NameSpaceOID, []byte("retro-daily-run:"+day+":"+zone)).String()
}

// Calendar days, not 24-hour durations, keep tomorrow and expiry correct across DST.
func dailyWindow(s DailySettingsData, now time.Time) (string, time.Time, error) {
	if e := validateDailySettings(&s); e != nil {
		return "", time.Time{}, e
	}
	zone, _ := time.LoadLocation(s.TimeZone)
	local := now.In(zone)
	scheduled := local
	slot := time.Date(scheduled.Year(), scheduled.Month(), scheduled.Day(), s.Hour, s.Minute, 0, 0, zone)
	if now.Before(slot) {
		scheduled = local.AddDate(0, 0, -1)
		slot = time.Date(scheduled.Year(), scheduled.Month(), scheduled.Day(), s.Hour, s.Minute, 0, 0, zone)
	}
	if slot.Hour() != s.Hour || slot.Minute() != s.Minute || slot.Day() != scheduled.Day() {
		return "", time.Time{}, conflict("the configured daily time does not exist on this local date")
	}
	if now.Before(slot) || now.Sub(slot) > 2*time.Hour {
		return "", time.Time{}, conflict("daily generation is outside its two-hour catch-up window")
	}
	target := time.Date(scheduled.Year(), scheduled.Month(), scheduled.Day(), 0, 0, 0, 0, zone)
	if s.Mode == "previous_evening" {
		target = target.AddDate(0, 0, 1)
	}
	expiry := target.AddDate(0, 0, 1)
	if !now.Before(expiry) {
		return "", time.Time{}, conflict("the scheduled daily result would already be expired")
	}
	return target.Format("2006-01-02"), expiry, nil
}
func (u *unit) getDailyRun(ctx context.Context, key string) (*DailyRun, error) {
	var raw, delivery []byte
	e := u.tx.QueryRow(ctx, "SELECT data,delivery FROM retro.daily_runs WHERE id=$1", key).Scan(&raw, &delivery)
	if errors.Is(e, pgx.ErrNoRows) {
		return nil, nil
	}
	if e != nil {
		return nil, e
	}
	var run DailyRun
	if e = json.Unmarshal(raw, &run); e != nil {
		return nil, e
	}
	if len(delivery) > 0 {
		run.Delivery = &DailyDelivery{}
		e = json.Unmarshal(delivery, run.Delivery)
	}
	return &run, e
}
func readDailyRun(ctx context.Context, u *unit, in DailyReadInput) (DailyRunResult, error) {
	if e := date(in.Day); e != nil {
		return DailyRunResult{}, e
	}
	if _, e := time.LoadLocation(in.TimeZone); e != nil || in.TimeZone == "" || in.TimeZone == "Local" || len(in.TimeZone) > 100 {
		return DailyRunResult{}, invalid("invalid daily time_zone")
	}
	run, e := u.getDailyRun(ctx, dailyRunID(in.Day, in.TimeZone))
	return DailyRunResult{run}, e
}
func generateDailyRun(ctx context.Context, u *unit, in DailyGenerateInput) (DailyRunResult, error) {
	var result DailyRunResult
	s, e := u.getDailySettings(ctx)
	if e != nil {
		return result, e
	}
	if !s.Enabled || in.ExpectedSettingsVersion != s.Version {
		return result, conflict("daily settings changed or generation is disabled")
	}
	now := time.Now().UTC()
	day, expiry, e := dailyWindow(s.DailySettingsData, now)
	if e != nil {
		return result, e
	}
	key := dailyRunID(day, s.TimeZone)
	existing, e := u.getDailyRun(ctx, key)
	if e != nil {
		return result, e
	}
	if existing != nil {
		if existing.SettingsVersion != s.Version {
			return result, conflict("this day was already generated under earlier settings; new settings apply to the next day")
		}
		return DailyRunResult{existing}, nil
	}
	query := SuggestInput{Day: day}
	choices, e := suggest(ctx, u, query)
	if e != nil {
		return result, e
	}
	query.ExpectedPreferencesVersion = &choices.PreferencesSource.Version
	query.Occasion = choices.EffectiveOccasion
	run := DailyRun{ID: key, Day: day, TimeZone: s.TimeZone, SettingsVersion: s.Version, ExpiresAt: expiry, Query: query, Suggestions: choices}
	raw, e := json.Marshal(run)
	if e != nil {
		return result, e
	}
	if _, e = u.tx.Exec(ctx, "INSERT INTO retro.daily_runs(id,day,time_zone,settings_version,expires_at,data) VALUES($1,$2,$3,$4,$5,$6)", key, day, s.TimeZone, s.Version, expiry, raw); e != nil {
		return result, e
	}
	result.Run = &run
	return result, u.audit(ctx, "daily_run", key, nil, run)
}
func claimDailyDelivery(ctx context.Context, u *unit, in DailyClaimInput) (DailyClaimResult, error) {
	// shortcut: one authorized attempt, not guaranteed provider delivery; add provider idempotency adapters when deployed senders are known.
	var result DailyClaimResult
	key, e := id(in.RunID)
	if e != nil {
		return result, e
	}
	claim, e := id(in.ClaimID)
	if e != nil {
		return result, e
	}
	run, e := u.getDailyRun(ctx, key)
	if e != nil {
		return result, e
	}
	if run == nil {
		return result, notFound()
	}
	result.Run = *run
	if run.Delivery != nil {
		return result, nil
	}
	s, e := u.getDailySettings(ctx)
	if e != nil {
		return result, e
	}
	if !s.Enabled || s.Version != run.SettingsVersion || s.DeliveryTarget == "" || !time.Now().Before(run.ExpiresAt) {
		return result, conflict("daily delivery is disabled, expired or needs current settings")
	}
	targetDay, _, e := dailyWindow(s.DailySettingsData, time.Now())
	if e != nil {
		return result, e
	}
	if targetDay != run.Day || s.TimeZone != run.TimeZone {
		return result, conflict("delivery belongs to a different scheduled day")
	}
	// Recheck ranked source constraints before reserving an external delivery.
	current, e := suggest(ctx, u, run.Query)
	if e != nil {
		return result, e
	}
	if len(current.Items) != len(run.Suggestions.Items) {
		return result, conflict("daily choices changed; use fresh choices in Retro")
	}
	for n, option := range current.Items {
		old := run.Suggestions.Items[n]
		a, _ := json.Marshal(option.Items)
		b, _ := json.Marshal(old.Items)
		if option.Fingerprint != old.Fingerprint || string(a) != string(b) {
			return result, conflict("daily pieces changed; use fresh choices in Retro")
		}
	}
	delivery := DailyDelivery{ClaimID: claim, Status: "claimed", Target: s.DeliveryTarget, UpdatedAt: time.Now().UTC()}
	raw, e := json.Marshal(delivery)
	if e != nil {
		return result, e
	}
	if _, e = u.tx.Exec(ctx, "UPDATE retro.daily_runs SET delivery=$2 WHERE id=$1", key, raw); e != nil {
		return result, e
	}
	result.Run.Delivery = &delivery
	result.SendAllowed = true
	return result, u.audit(ctx, "daily_run", key, run, result.Run)
}
func completeDailyDelivery(ctx context.Context, u *unit, in DailyCompleteInput) (DailyRunResult, error) {
	var result DailyRunResult
	key, e := id(in.RunID)
	if e != nil {
		return result, e
	}
	claim, e := id(in.ClaimID)
	if e != nil {
		return result, e
	}
	receipt, source := strings.TrimSpace(in.Receipt), strings.TrimSpace(in.Source)
	if receipt == "" || len(receipt) > 500 || source == "" || len(source) > 500 {
		return result, invalid("record the bounded provider receipt and actual delivery tool-call source")
	}
	run, e := u.getDailyRun(ctx, key)
	if e != nil {
		return result, e
	}
	if run == nil || run.Delivery == nil || run.Delivery.ClaimID != claim {
		return result, conflict("delivery claim does not match this daily result")
	}
	if run.Delivery.Status == "sent" {
		if run.Delivery.Receipt != receipt || run.Delivery.Source != source {
			return result, conflict("a different delivery receipt was already recorded")
		}
		return DailyRunResult{run}, nil
	}
	before := *run
	previous := *run.Delivery
	before.Delivery = &previous
	run.Delivery.Status = "sent"
	run.Delivery.Receipt = receipt
	run.Delivery.Source = source
	run.Delivery.UpdatedAt = time.Now().UTC()
	raw, e := json.Marshal(run.Delivery)
	if e != nil {
		return result, e
	}
	if _, e = u.tx.Exec(ctx, "UPDATE retro.daily_runs SET delivery=$2 WHERE id=$1", key, raw); e != nil {
		return result, e
	}
	return DailyRunResult{run}, u.audit(ctx, "daily_run", key, before, run)
}
