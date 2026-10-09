package engine

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type FeedbackData struct {
	Rating        *int   `json:"rating,omitempty"`
	ComfortRating *int   `json:"comfort_rating,omitempty"`
	StyleRating   *int   `json:"style_rating,omitempty"`
	Warmth        string `json:"warmth"`
	Comment       string `json:"comment,omitempty"`
}
type Feedback struct {
	FeedbackData
	ID            string     `json:"id"`
	OutfitID      string     `json:"outfit_id"`
	OutfitVersion int64      `json:"outfit_version"`
	Version       int64      `json:"version"`
	UpdatedAt     *time.Time `json:"updated_at,omitempty"`
}
type FeedbackResult struct {
	Feedback             Feedback `json:"feedback"`
	CurrentOutfitVersion int64    `json:"current_outfit_version"`
	OutfitState          string   `json:"outfit_state"`
}
type FeedbackPatchInput struct {
	PatchInput
	OutfitID              string `json:"outfit_id"`
	ExpectedOutfitVersion int64  `json:"expected_outfit_version"`
}

func feedbackIdentity(outfitID string) string {
	return uuid.NewSHA1(uuid.NameSpaceOID, []byte("retro-feedback:"+outfitID)).String()
}
func (u *unit) getFeedback(ctx context.Context, value string) (Feedback, error) {
	var f Feedback
	var attrs []byte
	e := u.tx.QueryRow(ctx, `SELECT id::text,outfit_id::text,outfit_version,version,attributes,updated_at FROM retro.outfit_feedback WHERE id=$1`, value).Scan(&f.ID, &f.OutfitID, &f.OutfitVersion, &f.Version, &attrs, &f.UpdatedAt)
	if e != nil {
		return f, e
	}
	e = json.Unmarshal(attrs, &f.FeedbackData)
	return f, e
}
func readFeedback(ctx context.Context, u *unit, in GetInput) (FeedbackResult, error) {
	var r FeedbackResult
	o, e := u.getOutfit(ctx, in.ID)
	if e != nil {
		return r, e
	}
	r.CurrentOutfitVersion = o.Version
	r.OutfitState = o.State
	r.Feedback, e = u.getFeedback(ctx, feedbackIdentity(o.ID))
	if errors.Is(e, pgx.ErrNoRows) {
		r.Feedback = Feedback{FeedbackData: FeedbackData{Warmth: "unknown"}, ID: feedbackIdentity(o.ID), OutfitID: o.ID, OutfitVersion: o.Version}
		e = nil
	}
	return r, e
}
func validateFeedback(f *FeedbackData) error {
	for _, v := range []*int{f.Rating, f.ComfortRating, f.StyleRating} {
		if v != nil && (*v < 1 || *v > 5) {
			return invalid("feedback ratings must be between 1 and 5")
		}
	}
	if f.Warmth == "" {
		f.Warmth = "unknown"
	}
	f.Comment = strings.TrimSpace(f.Comment)
	if !oneOf(f.Warmth, "unknown", "too_cold", "comfortable", "too_warm") || len(f.Comment) > 1000 {
		return invalid("unsupported feedback warmth or oversized comment")
	}
	return nil
}
func updateFeedback(ctx context.Context, u *unit, in FeedbackPatchInput) (FeedbackResult, error) {
	var r FeedbackResult
	key, e := id(in.ID)
	if e != nil {
		return r, e
	}
	before, e := readFeedback(ctx, u, GetInput{ID: in.OutfitID})
	if e != nil {
		return r, e
	}
	if key != before.Feedback.ID {
		return r, notFound()
	}
	if e = version(in.ExpectedOutfitVersion, before.CurrentOutfitVersion); e != nil {
		return r, e
	}
	if before.OutfitState != "worn" {
		return r, conflict("feedback changes require an actual worn outfit; restore void history first")
	}
	if in.ExpectedVersion < 0 {
		return r, invalid("feedback expected_version cannot be negative")
	}
	if in.ExpectedVersion != before.Feedback.Version {
		return r, conflict("feedback changed; refresh before editing")
	}
	data := before.Feedback.FeedbackData
	if e = patchFields(&data, in.Patch, "rating", "comfort_rating", "style_rating", "warmth", "comment"); e != nil {
		return r, e
	}
	if e = validateFeedback(&data); e != nil {
		return r, e
	}
	attrs, e := json.Marshal(data)
	if e != nil {
		return r, e
	}
	if _, e = u.tx.Exec(ctx, `INSERT INTO retro.outfit_feedback(id,outfit_id,outfit_version,attributes) VALUES($1,$2,$3,$4) ON CONFLICT(id) DO UPDATE SET outfit_version=EXCLUDED.outfit_version,attributes=EXCLUDED.attributes,version=retro.outfit_feedback.version+1,updated_at=now()`, key, before.Feedback.OutfitID, before.CurrentOutfitVersion, attrs); e != nil {
		return r, e
	}
	r, e = readFeedback(ctx, u, GetInput{ID: before.Feedback.OutfitID})
	if e != nil {
		return r, e
	}
	var previous any
	if before.Feedback.Version > 0 {
		previous = before.Feedback
	}
	return r, u.audit(ctx, "feedback", key, previous, r.Feedback)
}
