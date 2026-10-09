package engine

import (
	"testing"
	"time"
)

func TestDailyCalendarWindowUsesLocalDaysAndBoundedCatchUp(t *testing.T) {
	zone, _ := time.LoadLocation("America/Los_Angeles")
	s := DailySettingsData{Mode: "previous_evening", Hour: 20, TimeZone: zone.String()}
	now := time.Date(2026, 10, 31, 20, 15, 0, 0, zone)
	day, expiry, e := dailyWindow(s, now)
	if e != nil || day != "2026-11-01" || expiry.In(zone).Format("2006-01-02 15:04") != "2026-11-02 00:00" {
		t.Fatalf("DST day calculation: %s %v %v", day, expiry, e)
	}
	if expiry.Sub(time.Date(2026, 11, 1, 0, 0, 0, 0, zone)) != 25*time.Hour {
		t.Fatal("fall-back day was treated as 24 hours")
	}
	s.Mode = "morning"
	s.Hour = 7
	day, _, e = dailyWindow(s, time.Date(2026, 3, 8, 7, 5, 0, 0, zone))
	if e != nil || day != "2026-03-08" {
		t.Fatal("morning date crossed a calendar day")
	}
	for _, clock := range []time.Time{time.Date(2026, 3, 8, 6, 59, 0, 0, zone), time.Date(2026, 3, 8, 9, 1, 0, 0, zone)} {
		if _, _, e = dailyWindow(s, clock); e == nil {
			t.Fatal("unbounded catch-up accepted")
		}
	}
	s.Hour, s.Minute = 2, 30
	if _, _, e = dailyWindow(s, time.Date(2026, 3, 8, 3, 35, 0, 0, zone)); e == nil {
		t.Fatal("a nonexistent local time was silently moved")
	}
	s.Mode, s.Hour, s.Minute = "previous_evening", 23, 50
	late := time.Date(2026, 10, 10, 0, 20, 0, 0, zone)
	day, expiry, e = dailyWindow(s, late)
	if e != nil || day != "2026-10-10" || expiry.In(zone).Format("2006-01-02 15:04") != "2026-10-11 00:00" {
		t.Fatal("previous-evening catch-up crossed into the wrong target day")
	}
	s.Mode = "morning"
	if _, _, e = dailyWindow(s, late); e == nil {
		t.Fatal("an already-expired morning snapshot was generated")
	}
	if dailyRunID(day, zone.String()) == dailyRunID(day, "UTC") || dailyRunID(day, "UTC") != dailyRunID(day, "UTC") {
		t.Fatal("daily identity scope is unstable")
	}
	s.TimeZone = "invented/zone"
	if validateDailySettings(&s) == nil {
		t.Fatal("invalid zone accepted")
	}
}
