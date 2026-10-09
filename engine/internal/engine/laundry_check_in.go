package engine

import (
	"context"
	"encoding/json"
	"time"
)

type LaundryReminder struct {
	WearDays     *int `json:"wear_days,omitempty"`
	IntervalDays *int `json:"interval_days,omitempty"`
}
type LaundryCheckInInput struct {
	TimeZone  string `json:"time_zone"`
	GarmentID string `json:"garment_id,omitempty"`
}
type LaundryCleaningSource struct {
	ID          string    `json:"id"`
	Version     int64     `json:"version"`
	CompletedAt time.Time `json:"completed_at"`
}
type LaundryWearStats struct {
	WearDays          int64 `json:"wear_days"`
	WearEvents        int64 `json:"wear_events"`
	SameDayWearDays   int64 `json:"same_day_wear_days"`
	SameDayWearEvents int64 `json:"same_day_wear_events"`
}
type LaundryCheckInItem struct {
	GarmentID         string                 `json:"garment_id"`
	GarmentVersion    int64                  `json:"garment_version"`
	Name              string                 `json:"name"`
	Availability      string                 `json:"availability"`
	ArchivedAt        *time.Time             `json:"archived_at"`
	Reminder          *LaundryReminder       `json:"reminder"`
	LastCleaning      *LaundryCleaningSource `json:"last_cleaning"`
	Wears             *LaundryWearStats      `json:"wears_since_cleaning"`
	DaysSinceCleaning *int                   `json:"days_since_cleaning"`
	Due               bool                   `json:"due"`
	DueReasons        []string               `json:"due_reasons"`
}
type LaundryCheckIn struct {
	GeneratedAt    time.Time            `json:"generated_at"`
	TimeZone       string               `json:"time_zone"`
	Coverage       string               `json:"coverage"`
	InventoryCount int                  `json:"inventory_count"`
	Items          []LaundryCheckInItem `json:"items"`
}

func validateLaundryReminder(r *LaundryReminder) error {
	if r == nil {
		return nil
	}
	if r.WearDays == nil && r.IntervalDays == nil || r.WearDays != nil && (*r.WearDays < 1 || *r.WearDays > 100) || r.IntervalDays != nil && (*r.IntervalDays < 1 || *r.IntervalDays > 365) {
		return invalid("choose a wear-day threshold from 1-100 and/or a calendar-day interval from 1-365; null removes the reminder")
	}
	return nil
}
func laundryCalendarDays(cleaned, now time.Time, zone *time.Location) int {
	start, _ := time.Parse("2006-01-02", cleaned.In(zone).Format("2006-01-02"))
	end, _ := time.Parse("2006-01-02", now.In(zone).Format("2006-01-02"))
	return int(end.Sub(start) / (24 * time.Hour))
}
func laundryReminderReasons(item LaundryCheckInItem) []string {
	reasons := []string{}
	if item.Reminder == nil || item.LastCleaning == nil || item.Wears == nil || item.DaysSinceCleaning == nil || item.ArchivedAt != nil || item.Availability == "washing" {
		return reasons
	}
	if threshold := item.Reminder.WearDays; threshold != nil && item.Wears.WearDays >= int64(*threshold) {
		reasons = append(reasons, "wear_threshold")
	}
	if interval := item.Reminder.IntervalDays; interval != nil && *item.DaysSinceCleaning >= *interval {
		reasons = append(reasons, "interval_threshold")
	}
	return reasons
}
func checkInLaundry(ctx context.Context, u *unit, in LaundryCheckInInput) (LaundryCheckIn, error) {
	result := LaundryCheckIn{GeneratedAt: time.Now().UTC(), TimeZone: in.TimeZone, Coverage: "active_garments_only", Items: []LaundryCheckInItem{}}
	zone, e := time.LoadLocation(in.TimeZone)
	if e != nil || in.TimeZone == "" || in.TimeZone == "Local" || len(in.TimeZone) > 100 {
		return result, invalid("choose an explicit IANA time zone")
	}
	if in.GarmentID != "" {
		if in.GarmentID, e = id(in.GarmentID); e != nil {
			return result, e
		}
		result.Coverage = "explicit_garment"
	}
	// Share the completion clock and establish the read snapshot before deriving date-based facts.
	if e = u.tx.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&result.GeneratedAt); e != nil {
		return result, e
	}
	result.GeneratedAt = result.GeneratedAt.UTC()
	// Wear records have local dates, not wear instants. Same-cleaning-day records cannot establish order.
	rows, e := u.tx.Query(ctx, `SELECT g.id::text,g.version,g.name,g.availability,g.archived_at,g.attributes->'laundry_reminder',
 c.id::text,c.version,c.completed_at,w.days,w.events,w.same_days,w.same_events
 FROM retro.garments g
 LEFT JOIN LATERAL (
   SELECT l.id,l.version,l.completed_at FROM retro.laundry_items i JOIN retro.laundry_loads l ON l.id=i.load_id
   WHERE i.garment_id=g.id AND l.state='completed' ORDER BY l.completed_at DESC,l.id DESC LIMIT 1
 ) c ON true
 LEFT JOIN LATERAL (
   SELECT count(DISTINCT o.day) FILTER(WHERE o.day>(c.completed_at AT TIME ZONE o.time_zone)::date) AS days,
     count(*) FILTER(WHERE o.day>(c.completed_at AT TIME ZONE o.time_zone)::date) AS events,
     count(DISTINCT o.day) FILTER(WHERE o.day=(c.completed_at AT TIME ZONE o.time_zone)::date) AS same_days,
     count(*) FILTER(WHERE o.day=(c.completed_at AT TIME ZONE o.time_zone)::date) AS same_events
   FROM retro.outfit_items i JOIN retro.outfits o ON o.id=i.outfit_id
   WHERE i.garment_id=g.id AND o.state='worn' AND c.completed_at IS NOT NULL
     AND o.day<=($2::timestamptz AT TIME ZONE o.time_zone)::date
 ) w ON true
 WHERE ($1<>'' OR g.archived_at IS NULL) AND ($1='' OR g.id=NULLIF($1,'')::uuid)
 ORDER BY g.id LIMIT 2001`, in.GarmentID, result.GeneratedAt)
	if e != nil {
		return result, e
	}
	defer rows.Close()
	for rows.Next() {
		if len(result.Items) == 2000 {
			return result, invalid("laundry check-in supports at most 2000 active garments; inspect an explicit garment instead")
		}
		var item LaundryCheckInItem
		var reminder []byte
		var cleanID *string
		var cleanVersion *int64
		var cleaned *time.Time
		var wears LaundryWearStats
		if e = rows.Scan(&item.GarmentID, &item.GarmentVersion, &item.Name, &item.Availability, &item.ArchivedAt, &reminder,
			&cleanID, &cleanVersion, &cleaned, &wears.WearDays, &wears.WearEvents, &wears.SameDayWearDays, &wears.SameDayWearEvents); e != nil {
			return result, e
		}
		if len(reminder) > 0 {
			if e = json.Unmarshal(reminder, &item.Reminder); e != nil {
				return result, e
			}
		}
		if e = validateLaundryReminder(item.Reminder); e != nil {
			return result, e
		}
		if cleaned != nil && cleanID != nil && cleanVersion != nil {
			item.LastCleaning = &LaundryCleaningSource{*cleanID, *cleanVersion, *cleaned}
			item.Wears = &wears
			days := laundryCalendarDays(*cleaned, result.GeneratedAt, zone)
			item.DaysSinceCleaning = &days
		}
		item.DueReasons = laundryReminderReasons(item)
		item.Due = len(item.DueReasons) > 0
		result.Items = append(result.Items, item)
	}
	if e = rows.Err(); e != nil {
		return result, e
	}
	if in.GarmentID != "" && len(result.Items) == 0 {
		return result, notFound()
	}
	result.InventoryCount = len(result.Items)
	return result, nil
}
