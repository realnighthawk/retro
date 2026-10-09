package engine

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type DaySelection struct {
	ID        string     `json:"id"`
	Day       string     `json:"day"`
	Version   int64      `json:"version"`
	OutfitID  *string    `json:"outfit_id"`
	TimeZone  string     `json:"time_zone"`
	UpdatedAt *time.Time `json:"updated_at"`
	Outfit    *Outfit    `json:"outfit"`
	Problem   *string    `json:"problem"`
}
type DaySelectionInput struct {
	EditInput
	Day                   string  `json:"day"`
	OutfitID              *string `json:"outfit_id"`
	ExpectedOutfitVersion *int64  `json:"expected_outfit_version,omitempty"`
}
type DaySelectionResult struct {
	Selection DaySelection `json:"selection"`
}

func daySelectionID(day string) string {
	return uuid.NewSHA1(uuid.NameSpaceOID, []byte("retro-day-selection:"+day)).String()
}
func (u *unit) getDaySelection(ctx context.Context, day string) (DaySelection, error) {
	s := DaySelection{ID: daySelectionID(day), Day: day}
	e := u.tx.QueryRow(ctx, `SELECT version,outfit_id::text,time_zone,updated_at FROM retro.day_selections WHERE id=$1 AND day=$2`, s.ID, day).Scan(&s.Version, &s.OutfitID, &s.TimeZone, &s.UpdatedAt)
	if errors.Is(e, pgx.ErrNoRows) {
		return s, nil
	}
	if e != nil || s.OutfitID == nil {
		return s, e
	}
	o, e := u.getOutfit(ctx, *s.OutfitID)
	if e != nil {
		return s, e
	}
	s.Outfit = &o
	message := ""
	switch {
	case o.State == "void":
		message = "The selected outfit was voided. Choose another saved plan or clear the selection."
	case o.Day != day || o.TimeZone != s.TimeZone:
		message = "The selected outfit's date or time zone changed. Review it and choose again."
	case o.State == "planned":
		for _, item := range o.Items {
			if item.Snapshot.ArchivedAt != nil || item.Snapshot.Availability != "ready" {
				message = "Some selected pieces are no longer ready. Review the plan before recording a wear."
				break
			}
		}
	}
	if message != "" {
		s.Problem = &message
	}
	return s, nil
}
func updateDaySelection(ctx context.Context, u *unit, in DaySelectionInput) (DaySelectionResult, error) {
	var result DaySelectionResult
	if e := date(in.Day); e != nil {
		return result, e
	}
	key, e := id(in.ID)
	if e != nil {
		return result, e
	}
	if key != daySelectionID(in.Day) {
		return result, invalid("selection identity does not match its local day")
	}
	before, e := u.getDaySelection(ctx, in.Day)
	if e != nil {
		return result, e
	}
	if in.ExpectedVersion < 0 {
		return result, invalid("selection expected_version cannot be negative")
	}
	if in.ExpectedVersion != before.Version {
		return result, conflict("the daily selection changed; refresh before choosing again")
	}
	zone := before.TimeZone
	if in.OutfitID != nil {
		o, e := u.getOutfit(ctx, *in.OutfitID)
		if e != nil {
			return result, e
		}
		if in.ExpectedOutfitVersion == nil {
			return result, invalid("review the outfit version before selecting a plan")
		}
		if e = version(*in.ExpectedOutfitVersion, o.Version); e != nil {
			return result, e
		}
		if o.Day != in.Day || o.State != "planned" {
			return result, conflict("select a saved plan for this local day; selecting never records a wear")
		}
		for _, item := range o.Items {
			if item.Snapshot.ArchivedAt != nil || item.Snapshot.Availability != "ready" {
				return result, conflict("review unavailable pieces before selecting this plan")
			}
		}
		zone = o.TimeZone
		in.OutfitID = &o.ID
	} else if in.ExpectedOutfitVersion != nil || before.Version == 0 {
		return result, invalid("clear an existing selection without an outfit version")
	}
	_, e = u.tx.Exec(ctx, `INSERT INTO retro.day_selections(id,day,outfit_id,time_zone) VALUES($1,$2,$3,$4)
	 ON CONFLICT(id) DO UPDATE SET outfit_id=EXCLUDED.outfit_id,time_zone=EXCLUDED.time_zone,version=retro.day_selections.version+1,updated_at=now()`, key, in.Day, in.OutfitID, zone)
	if e != nil {
		return result, e
	}
	result.Selection, e = u.getDaySelection(ctx, in.Day)
	if e != nil {
		return result, e
	}
	var previous any
	if before.Version > 0 {
		previous = before
	}
	return result, u.audit(ctx, "day_selection", key, previous, result.Selection)
}
