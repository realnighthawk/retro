package engine_test

import (
	"context"
	"encoding/json"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/nighthawklabs/retro/engine/internal/engine"
)

func TestIntegrationDailyGenerationAndDeliveryReplayNeverGrantAnotherSend(t *testing.T) {
	s := integrationService(t, nil)
	ctx := context.Background()
	pool, e := pgxpool.New(ctx, os.Getenv("TEST_DATABASE_URL"))
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(pool.Close)
	before := execute[engine.DailySettingsResult](t, s, "wardrobe_daily_settings_get", map[string]any{}).Settings
	now := time.Now().UTC()
	day := now.Format("2006-01-02")
	existing := execute[engine.DailyRunResult](t, s, "wardrobe_daily_get", map[string]any{"day": day, "time_zone": "UTC"})
	if existing.Run != nil {
		t.Skip("test preserves an existing daily result")
	}
	t.Cleanup(func() {
		current := execute[engine.DailySettingsResult](t, s, "wardrobe_daily_settings_get", map[string]any{}).Settings
		body := edit(current.ID, current.Version)
		body["patch"] = before.DailySettingsData
		_ = execute[engine.DailySettingsResult](t, s, "wardrobe_daily_settings_update", body)
		_, _ = pool.Exec(ctx, "DELETE FROM retro.daily_runs WHERE day=$1 AND time_zone='UTC'", day)
	})
	patch := edit(before.ID, before.Version)
	patch["patch"] = engine.DailySettingsData{Enabled: true, Mode: "morning", Hour: now.Hour(), Minute: now.Minute(), TimeZone: "UTC", DeliveryTarget: "fixture-only inbox"}
	settings := execute[engine.DailySettingsResult](t, s, "wardrobe_daily_settings_update", patch).Settings
	var wg sync.WaitGroup
	runs := make(chan *engine.DailyRun, 4)
	errs := make(chan error, 4)
	for n := 0; n < 4; n++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			raw, _ := json.Marshal(map[string]any{"idempotency_key": uuid.NewString(), "expected_settings_version": settings.Version})
			reply, e := s.Execute(ctx, "wardrobe_daily_generate", raw)
			var result engine.DailyRunResult
			if e == nil {
				e = json.Unmarshal(reply, &result)
			}
			if e != nil {
				errs <- e
			} else {
				runs <- result.Run
			}
		}()
	}
	wg.Wait()
	close(runs)
	close(errs)
	for e := range errs {
		t.Fatal(e)
	}
	var run *engine.DailyRun
	for generated := range runs {
		if generated == nil {
			t.Fatal("missing daily result")
		}
		if run != nil && generated.ID != run.ID {
			t.Fatal("concurrent generation duplicated the day")
		}
		run = generated
	}
	if run == nil || run.Day != day || run.Query.ExpectedPreferencesVersion == nil {
		t.Fatal("missing ranked-source snapshot")
	}
	claim := map[string]any{"idempotency_key": uuid.NewString(), "run_id": run.ID, "claim_id": uuid.NewString()}
	first := execute[engine.DailyClaimResult](t, s, "wardrobe_daily_delivery_claim", claim)
	if !first.SendAllowed || first.Run.Delivery == nil {
		t.Fatal("first claim did not reserve delivery")
	}
	replay := execute[engine.DailyClaimResult](t, s, "wardrobe_daily_delivery_claim", claim)
	if replay.SendAllowed {
		t.Fatal("lost claim reply authorized another send")
	}
	second := map[string]any{"idempotency_key": uuid.NewString(), "run_id": run.ID, "claim_id": uuid.NewString()}
	if execute[engine.DailyClaimResult](t, s, "wardrobe_daily_delivery_claim", second).SendAllowed {
		t.Fatal("a new attempt bypassed the daily delivery reservation")
	}
	complete := map[string]any{"idempotency_key": uuid.NewString(), "run_id": run.ID, "claim_id": claim["claim_id"], "receipt": "synthetic-provider-message", "source": "fixture-turn:act:5"}
	_ = execute[engine.DailyRunResult](t, s, "wardrobe_daily_delivery_complete", complete)
	after := execute[engine.DailyRunResult](t, s, "wardrobe_daily_get", map[string]any{"day": day, "time_zone": "UTC"})
	if after.Run.Delivery.Status != "sent" || after.Run.Delivery.Receipt != "synthetic-provider-message" {
		t.Fatal("durable receipt missing")
	}
	bad := edit(settings.ID, settings.Version)
	bad["patch"] = map[string]any{"enabled": false}
	disabled := execute[engine.DailySettingsResult](t, s, "wardrobe_daily_settings_update", bad).Settings
	errorCode(t, s, "wardrobe_daily_generate", map[string]any{"idempotency_key": uuid.NewString(), "expected_settings_version": disabled.Version}, "conflict")
	errorCode(t, s, "wardrobe_daily_settings_update", bad, "conflict")
}
