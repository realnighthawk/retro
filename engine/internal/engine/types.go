package engine

import (
	"encoding/json"
	"time"
)

type Meta struct {
	IdempotencyKey string `json:"idempotency_key"`
}
type GetInput struct {
	ID string `json:"id"`
}
type EditInput struct {
	Meta
	ID              string `json:"id"`
	ExpectedVersion int64  `json:"expected_version"`
}
type PatchInput struct {
	EditInput
	Patch map[string]json.RawMessage `json:"patch"`
}
type GarmentAttributes struct {
	Subtype         string           `json:"subtype,omitempty"`
	Colours         []string         `json:"colours,omitempty"`
	Warmth          string           `json:"warmth,omitempty"`
	Seasons         []string         `json:"seasons,omitempty"`
	Formality       string           `json:"formality,omitempty"`
	Material        string           `json:"material,omitempty"`
	Brand           string           `json:"brand,omitempty"`
	Notes           string           `json:"notes,omitempty"`
	Favourite       bool             `json:"favourite,omitempty"`
	MediaIDs        []string         `json:"media_ids,omitempty"`
	Care            *CareSettings    `json:"care,omitempty"`
	LaundryReminder *LaundryReminder `json:"laundry_reminder,omitempty"`
}
type GarmentData struct {
	Name         string `json:"name"`
	Category     string `json:"category"`
	Availability string `json:"availability,omitempty"`
	GarmentAttributes
}
type WearStats struct {
	WearDays   int64   `json:"wear_days"`
	WearEvents int64   `json:"wear_events"`
	LastWornOn *string `json:"last_worn_on"`
}
type Garment struct {
	GarmentData
	ID         string     `json:"id"`
	Version    int64      `json:"version"`
	ArchivedAt *time.Time `json:"archived_at"`
	CreatedAt  time.Time  `json:"created_at"`
	UpdatedAt  time.Time  `json:"updated_at"`
	WearStats
}
type CreateGarmentInput struct {
	Meta
	ID string `json:"id,omitempty"`
	GarmentData
}
type GarmentResult struct {
	Garment Garment `json:"garment"`
}
type ListInput struct {
	Limit  int    `json:"limit,omitempty"`
	Cursor string `json:"cursor,omitempty"`
}
type GarmentListInput struct {
	ListInput
	Search          string `json:"search,omitempty"`
	Category        string `json:"category,omitempty"`
	Availability    string `json:"availability,omitempty"`
	IncludeArchived bool   `json:"include_archived,omitempty"`
}
type Page[T any] struct {
	Items      []T     `json:"items"`
	NextCursor *string `json:"next_cursor"`
}
type Selection struct {
	GarmentID string `json:"garment_id"`
	Role      string `json:"role"`
}
type OutfitItem struct {
	Selection
	Snapshot *Garment `json:"snapshot"`
}
type OutfitData struct {
	Day      string `json:"day"`
	TimeZone string `json:"time_zone"`
	State    string `json:"state"`
	Label    string `json:"label,omitempty"`
	Occasion string `json:"occasion,omitempty"`
	Notes    string `json:"notes,omitempty"`
	Source   string `json:"source,omitempty"`
}
type Outfit struct {
	OutfitData
	ID            string       `json:"id"`
	Version       int64        `json:"version"`
	PreviousState string       `json:"previous_state,omitempty"`
	ConfirmedAt   *time.Time   `json:"confirmed_at"`
	CreatedAt     time.Time    `json:"created_at"`
	UpdatedAt     time.Time    `json:"updated_at"`
	Items         []OutfitItem `json:"items"`
}
type CreateOutfitInput struct {
	Meta
	ID string `json:"id,omitempty"`
	OutfitData
	Items []Selection `json:"items"`
}
type ConfirmInput struct {
	EditInput
	Items []Selection `json:"items,omitempty"`
}
type OutfitResult struct {
	Outfit Outfit `json:"outfit"`
}
type OutfitListInput struct {
	ListInput
	From      string `json:"from,omitempty"`
	To        string `json:"to,omitempty"`
	State     string `json:"state,omitempty"`
	GarmentID string `json:"garment_id,omitempty"`
}
type DayInput struct {
	Day         string `json:"day"`
	IncludeVoid bool   `json:"include_void,omitempty"`
}
type DayResult struct {
	Day       string       `json:"day"`
	Outfits   []Outfit     `json:"outfits"`
	Selection DaySelection `json:"selection"`
}
type HistoryInput struct {
	ListInput
	EntityType string `json:"entity_type"`
	ID         string `json:"id"`
}
type Change struct {
	ID         int64           `json:"id"`
	Actor      string          `json:"actor"`
	Operation  string          `json:"operation"`
	Before     json.RawMessage `json:"before"`
	After      json.RawMessage `json:"after"`
	OccurredAt time.Time       `json:"occurred_at"`
}
