package engine

import "context"

func (s *Service) registerOperations() {
	register(s, "laundry_check_in", "Read complete active wardrobe care check-ins (at most 2000) or one explicit garment: latest completed cleaning, definitely later wear dates, ambiguous same-day wears and opted-in review thresholds. Never marks dirty or sends notifications.", false, checkInLaundry)
	register(s, "laundry_preview", "Group active needs-wash garments by confirmed care for an explicit programme; unknown/incompatible care stays blocked.", false, previewLaundry)
	register(s, "laundry_create", "Plan a reviewed compatible load of 1-30 garments with source versions; never starts washing.", true, createLaundry)
	register(s, "laundry_get", "Read a laundry load and retained garment/care snapshots and progress timestamps.", false, func(c context.Context, u *unit, in GetInput) (LaundryResult, error) {
		v, e := u.getLaundry(c, in.ID)
		return LaundryResult{v}, e
	})
	register(s, "laundry_list", "Browse laundry plans/progress/history, optionally by state or garment, with scoped pagination.", false, listLaundry)
	register(s, "laundry_update", "Edit a planned load with current load and garment versions; active/completed loads cannot be edited.", true, updateLaundry)
	register(s, "laundry_progress", "Confirm the next step: planned to washing, washing to drying, drying to ready/completed. Dry cleaning completes when returned clean.", true, progressLaundry)
	register(s, "laundry_cancel", "Cancel an unfinished load; active garments return to needs wash without claiming completion.", true, cancelLaundry)
	register(s, "wardrobe_daily_settings_get", "Read desired daily automation settings; Temporal wake status is separate.", false, func(c context.Context, u *unit, _ struct{}) (DailySettingsResult, error) {
		v, e := u.getDailySettings(c)
		return DailySettingsResult{v}, e
	})
	register(s, "wardrobe_daily_settings_update", "Patch versioned daily automation settings; this does not arm a wake.", true, updateDailySettings)
	register(s, "wardrobe_daily_get", "Read the immutable daily choices and agent-recorded delivery status for a date/time zone.", false, readDailyRun)
	register(s, "wardrobe_daily_generate", "Generate/cache one rules-v2 result in the configured local two-hour window; no plan, wear or delivery.", true, generateDailyRun)
	register(s, "wardrobe_daily_delivery_claim", "Reserve one external delivery attempt per daily result. Only the first non-replayed claim grants send_allowed; uncertain sends must not be repeated.", true, claimDailyDelivery)
	register(s, "wardrobe_daily_delivery_complete", "Record a provider receipt against the existing delivery claim; never sends or retries a notification.", true, completeDailyDelivery)
	register(s, "wardrobe_context_get", "Read source-linked preferences and up to 10 explicit garments/5 outfits with feedback; coverage excludes unrequested records and connected services.", false, readContext)
	register(s, "preferences_get", "Read this wardrobe's shared preferences, including defaults, identity and version.", false, func(c context.Context, u *unit, _ struct{}) (PreferencesResult, error) {
		p, e := u.getPreferences(c)
		return PreferencesResult{p}, e
	})
	register(s, "preferences_update", "Patch shared preferences using the current version; null clears only lists or default occasion.", true, updatePreferences)
	register(s, "outfits_feedback_get", "Read explicit feedback for an outfit; version zero means no saved feedback.", false, readFeedback)
	register(s, "outfits_feedback_update", "Patch feedback for a worn outfit with feedback and outfit version checks; null clears optional values without deleting history.", true, updateFeedback)
	register(s, "garments_create", "Create an owned garment; a photograph is optional.", true, createGarment)
	register(s, "garments_get", "Read a garment, including archived items and confirmed wear totals.", false, func(c context.Context, u *unit, i GetInput) (GarmentResult, error) {
		g, e := u.getGarment(c, i.ID)
		return GarmentResult{g}, e
	})
	register(s, "garments_list", "Filter and paginate inventory in stable ID order.", false, listGarments)
	register(s, "garments_update", "Patch an active garment using the current version; null clears optional attributes.", true, updateGarment)
	register(s, "garments_archive", "Archive a garment without removing historical outfits.", true, func(c context.Context, u *unit, i EditInput) (GarmentResult, error) {
		return lifecycleGarment(c, u, i, false)
	})
	register(s, "garments_restore", "Restore an archived garment, retaining its availability.", true, func(c context.Context, u *unit, i EditInput) (GarmentResult, error) {
		return lifecycleGarment(c, u, i, true)
	})
	register(s, "outfits_create", "Create an explicit planned or worn outfit on a local date.", true, createOutfit)
	register(s, "outfits_get", "Read an outfit and its historical snapshots or current planned items.", false, func(c context.Context, u *unit, i GetInput) (OutfitResult, error) {
		o, e := u.getOutfit(c, i.ID)
		return OutfitResult{o}, e
	})
	register(s, "outfits_list", "Filter and paginate outfits; void records are excluded by default.", false, listOutfits)
	register(s, "outfits_update", "Correct date, context or actual garments with a version check and audit.", true, updateOutfit)
	register(s, "outfits_confirm", "Confirm a plan with its final selected garments; snapshot inventory facts.", true, confirmOutfit)
	register(s, "outfits_void", "Void a mistaken plan or wear without deleting its history.", true, func(c context.Context, u *unit, i EditInput) (OutfitResult, error) {
		return lifecycleOutfit(c, u, i, false)
	})
	register(s, "outfits_restore", "Explicitly restore a void outfit to its previous state.", true, func(c context.Context, u *unit, i EditInput) (OutfitResult, error) {
		return lifecycleOutfit(c, u, i, true)
	})
	register(s, "wardrobe_day_get", "Read plans, wears and the stable daily selection for a local date; an unset selection has version zero.", false, dayGet)
	register(s, "wardrobe_day_selection_update", "Select a reviewed saved plan for its day or explicitly clear the selection; versioned and idempotent, never records a wear.", true, updateDaySelection)
	register(s, "pairings_create", "Save a reusable combination of 2-30 real garments without creating a plan or wear.", true, createPairing)
	register(s, "pairings_get", "Read a saved pairing with current garment facts, including archived/unavailable pieces.", false, func(c context.Context, u *unit, i GetInput) (PairingResult, error) {
		p, e := u.getPairing(c, i.ID)
		return PairingResult{p}, e
	})
	register(s, "pairings_list", "Browse saved pairings, optionally linked to a garment, with query-scoped pagination.", false, listPairings)
	register(s, "pairings_update", "Edit a saved pairing with its current version; changing pieces requires active garments.", true, updatePairing)
	register(s, "pairings_archive", "Archive a pairing without changing its garments or outfit history.", true, func(c context.Context, u *unit, i EditInput) (PairingResult, error) {
		return lifecyclePairing(c, u, i, false)
	})
	register(s, "pairings_restore", "Restore a pairing; unavailable or archived pieces still need review before planning.", true, func(c context.Context, u *unit, i EditInput) (PairingResult, error) {
		return lifecyclePairing(c, u, i, true)
	})
	register(s, "wardrobe_suggest", "Rank distinct available combinations using saved preferences and version-matched rated wears through the requested date; enforce avoided colours/repeat rules without saving a plan or wear.", false, suggest)
	register(s, "wardrobe_analyze", "Summarize actual outfit history and wardrobe usage in a date range.", false, analyze)
	register(s, "history_list", "Read append-only audit for wardrobe records, including daily automation and laundry loads.", false, history)
	register(s, "media_prepare", "Reserve an immutable JPEG/PNG upload; stream bytes to upload_path separately.", true, func(c context.Context, u *unit, i MediaInput) (MediaResult, error) {
		if s.photos == nil {
			return MediaResult{}, &Error{"busy", "Photo storage is not configured"}
		}
		return prepareMedia(c, u, i)
	})
	register(s, "media_get", "Read photo processing status and authenticated content paths.", false, func(c context.Context, u *unit, i GetInput) (MediaResult, error) {
		m, e := u.getMedia(c, i.ID)
		return MediaResult{m}, e
	})
	register(s, "media_retry", "Retry failed processing with a version and new request key.", true, func(c context.Context, u *unit, i EditInput) (MediaResult, error) {
		if s.photos == nil {
			return MediaResult{}, &Error{"busy", "Photo storage is not configured"}
		}
		return retryMedia(c, u, i)
	})
}
