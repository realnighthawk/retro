package engine_test

import (
	"context"
	"encoding/json"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/nighthawklabs/retro/engine/internal/engine"
)

func TestIntegrationPreferencesRetryVersionAndAudit(t *testing.T) {
	s := integrationService(t, nil)
	before := execute[engine.PreferencesResult](t, s, "preferences_get", map[string]any{}).Preferences
	if before.ID != engine.PreferencesID || before.Version < 1 || before.PreferredColours == nil {
		t.Fatalf("invalid persisted preferences: %+v", before)
	}
	t.Cleanup(func() {
		current := execute[engine.PreferencesResult](t, s, "preferences_get", map[string]any{}).Preferences
		body := edit(current.ID, current.Version)
		body["patch"] = before.PreferencesData
		_ = execute[engine.PreferencesResult](t, s, "preferences_update", body)
	})
	body := edit(before.ID, before.Version)
	body["patch"] = map[string]any{"preferred_colours": []string{" Sage "}, "avoided_colours": []string{}, "avoid_repeat_days": 0, "prefer_underused_items": false}
	raw, _ := json.Marshal(body)
	var wg sync.WaitGroup
	results := make(chan []byte, 8)
	errs := make(chan error, 8)
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			result, e := s.Execute(context.Background(), "preferences_update", raw)
			if e != nil {
				errs <- e
				return
			}
			results <- result
		}()
	}
	wg.Wait()
	close(results)
	close(errs)
	for e := range errs {
		t.Fatal(e)
	}
	for result := range results {
		var saved engine.PreferencesResult
		if e := json.Unmarshal(result, &saved); e != nil {
			t.Fatal(e)
		}
		if saved.Preferences.Version != before.Version+1 || len(saved.Preferences.PreferredColours) != 1 || saved.Preferences.PreferredColours[0] != "Sage" || saved.Preferences.PreferUnderusedItems || saved.Preferences.AvoidRepeatDays != 0 {
			t.Fatal("concurrent retries changed preferences more than once or lost explicit settings")
		}
	}
	current := execute[engine.PreferencesResult](t, s, "preferences_get", map[string]any{}).Preferences
	if current.Version != before.Version+1 {
		t.Fatal("retries advanced the persisted version")
	}
	audit := execute[engine.Page[engine.Change]](t, s, "history_list", map[string]any{"entity_type": "preferences", "id": before.ID})
	if len(audit.Items) == 0 || audit.Items[0].Operation != "preferences_update" {
		t.Fatal("preference mutation has no audit")
	}
	var auditedBefore engine.Preferences
	if e := json.Unmarshal(audit.Items[0].Before, &auditedBefore); e != nil || auditedBefore.Version != before.Version {
		t.Fatal("preference audit lost original version")
	}
	changedPayload := edit(before.ID, current.Version)
	changedPayload["idempotency_key"] = body["idempotency_key"]
	changedPayload["patch"] = map[string]any{"variety": "high"}
	errorCode(t, s, "preferences_update", changedPayload, "conflict")
	body["idempotency_key"] = uuid.NewString()
	errorCode(t, s, "preferences_update", body, "conflict")
	wrongID := edit(uuid.NewString(), current.Version)
	wrongID["patch"] = map[string]any{"variety": "high"}
	errorCode(t, s, "preferences_update", wrongID, "not_found")
	_ = execute[engine.PreferencesResult](t, s, "preferences_update", map[string]any{
		"id": current.ID, "expected_version": current.Version, "idempotency_key": uuid.NewString(),
		"patch": map[string]any{"preferred_colours": nil},
	})
	cleared := execute[engine.PreferencesResult](t, s, "preferences_get", map[string]any{}).Preferences
	if cleared.PreferredColours == nil || len(cleared.PreferredColours) != 0 {
		t.Fatal("null did not clear the preference list")
	}
}
