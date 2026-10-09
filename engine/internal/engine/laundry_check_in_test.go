package engine

import (
	"encoding/json"
	"testing"
	"time"
)

func TestLaundryReminderThresholdsRequireOptInAndKnownBaseline(t *testing.T) {
	two, three, zero, large := 2, 3, 0, 366
	for _, reminder := range []*LaundryReminder{{}, {WearDays: &zero}, {IntervalDays: &large}} {
		if validateLaundryReminder(reminder) == nil {
			t.Fatal("invalid threshold accepted")
		}
	}
	reminder := &LaundryReminder{WearDays: &two, IntervalDays: &three}
	if validateLaundryReminder(nil) != nil || validateLaundryReminder(reminder) != nil {
		t.Fatal("off or valid reminder rejected")
	}
	item := LaundryCheckInItem{Availability: "ready", Reminder: reminder, LastCleaning: &LaundryCleaningSource{}, Wears: &LaundryWearStats{WearDays: 1, SameDayWearDays: 8}, DaysSinceCleaning: &two}
	if len(laundryReminderReasons(item)) != 0 {
		t.Fatal("ambiguous same-day wears advanced the reminder")
	}
	item.Wears.WearDays = 2
	if reasons := laundryReminderReasons(item); len(reasons) != 1 || reasons[0] != "wear_threshold" {
		t.Fatal("distinct wear threshold did not prompt review")
	}
	item.DaysSinceCleaning = &three
	if len(laundryReminderReasons(item)) != 2 {
		t.Fatal("calendar interval not evaluated")
	}
	item.Availability = "washing"
	if len(laundryReminderReasons(item)) != 0 {
		t.Fatal("active cleaning reminder not paused")
	}
	item.Availability = "ready"
	item.LastCleaning = nil
	if len(laundryReminderReasons(item)) != 0 {
		t.Fatal("unknown cleaning baseline became a known due date")
	}
	g := GarmentData{Name: "Tee", Category: "top", GarmentAttributes: GarmentAttributes{LaundryReminder: reminder}}
	if e := patchFields(&g, map[string]json.RawMessage{"laundry_reminder": json.RawMessage(`null`)}, "laundry_reminder"); e != nil || g.LaundryReminder != nil || g.Name != "Tee" {
		t.Fatal("removing a reminder lost other garment fields")
	}
}
func TestLaundryCalendarIntervalUsesDatesAcrossDaylightSavings(t *testing.T) {
	zone, e := time.LoadLocation("America/Los_Angeles")
	if e != nil {
		t.Fatal(e)
	}
	start := time.Date(2026, 3, 7, 23, 30, 0, 0, zone)
	end := time.Date(2026, 3, 9, 0, 30, 0, 0, zone)
	if laundryCalendarDays(start, end, zone) != 2 {
		t.Fatal("interval used elapsed 24-hour blocks instead of calendar dates")
	}
}
