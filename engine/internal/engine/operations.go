package engine

import "context"

func (s *Service) registerOperations() {
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
	register(s, "wardrobe_day_get", "Read all plans and wears for a date; a missing date is empty.", false, dayGet)
	register(s, "wardrobe_suggest", "Suggest distinct available combinations without recording a wear.", false, suggest)
	register(s, "wardrobe_analyze", "Summarize actual outfit history and wardrobe usage in a date range.", false, analyze)
	register(s, "history_list", "Read append-only audit for a garment, outfit or photograph.", false, history)
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
