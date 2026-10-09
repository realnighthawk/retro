import Foundation

extension WardrobeStore {
    func importGarment(_ id: String) async throws -> WardrobeGarment {
        guard WardrobeMediaPath.path(id: id) != nil else { throw WardrobeWriteError("Invalid garment identity.") }
        let result = await photos.currentGarment(id)
        guard isCurrentOwner, !Task.isCancelled, case .ok(let value) = result, value.garment.id == id, value.garment.version > 0, value.garment.archivedAt == nil,
              (value.garment.mediaIDs ?? []).count <= 10, Set(value.garment.mediaIDs ?? []).count == (value.garment.mediaIDs ?? []).count, (value.garment.mediaIDs ?? []).allSatisfy({ WardrobeMediaPath.path(id: $0) != nil }) else { throw WardrobeWriteError(result.problem ?? "Open an active, freshly loaded garment.") }
        return value.garment
    }
    func useExistingImport(_ entryID: String, garment candidate: WardrobeGarment) async throws {
        guard isCurrentOwner else { throw WardrobeWriteError("Sign in before reviewing this import.") }
        guard let entry = drafts.items.first(where: { $0.id == entryID }), entry.importPhoto != nil, entry.dependency == nil, entry.garment == nil, !writes.contains(entry.entityID) else { throw WardrobeWriteError("Use an existing item before saving the new garment.") }
        // A create may have been acknowledged just before its draft handoff was interrupted.
        let original = await photos.currentGarment(entry.entityID)
        guard case .failed(let code, _) = original, code == "not_found" else { throw WardrobeWriteError(original.problem ?? "This garment was already saved. Finish its photo or discard the import.") }
        let current = try await importGarment(candidate.id)
        guard current.version == candidate.version, current.mediaIDs == candidate.mediaIDs,
              !writes.contains(current.id), !photos.contains(current.id), !photos.drafts.contains(where: { $0.garment.id == current.id }),
              drafts.items.first(where: { $0.id == entryID })?.updatedAt == entry.updatedAt else { throw WardrobeWriteError("The item changed or has pending work. Refresh and review it again.") }
        try drafts.put(WardrobeSavedDraft(id: entry.id, entityID: current.id, garment: current, outfit: nil, confirming: false, garmentDraft: WardrobeGarmentDraft(current), outfitDraft: nil, importPhoto: entry.importPhoto))
    }
    func attachImport(_ entryID: String) async throws {
        guard isCurrentOwner else { throw WardrobeWriteError("Sign in before accepting this photo.") }
        guard var entry = drafts.items.first(where: { $0.id == entryID }), entry.importPhoto != nil, !writes.contains(entry.entityID) else { throw WardrobeWriteError("Wait for the garment's save to be acknowledged first.") }
        guard try !entry.hasImportEdits() else { throw WardrobeWriteError("Review later garment edits against the latest record in Pending saves before accepting the photo.") }
        let current = try await importGarment(entry.entityID)
        guard drafts.items.first(where: { $0.id == entryID })?.updatedAt == entry.updatedAt, !writes.contains(current.id) else { throw WardrobeWriteError("The import changed. Review it again.") }
        if entry.dependency == nil && entry.garment == nil {
            let adopted = WardrobeSavedDraft(id: entry.id, entityID: current.id, garment: current, outfit: nil, confirming: false, garmentDraft: entry.garmentDraft, outfitDraft: nil, importPhoto: entry.importPhoto, importMediaID: entry.importMediaID)
            try drafts.put(adopted)
            entry = drafts.items.first { $0.id == entryID }!
            guard try !entry.hasImportEdits() else { throw WardrobeWriteError("The garment was saved before this import's handoff finished. Review its kept edits against the latest record in Pending saves.") }
        }
        if photos.batches.contains(where: { $0.id == entryID }) { return }
        if let mediaID = entry.importMediaID {
            if (current.mediaIDs ?? []).contains(mediaID) { return }
            guard let photoDraft = photos.drafts.first(where: { $0.id == entryID }), photoDraft.photos.count == 1, photoDraft.photos[0].chosen.id == mediaID else { throw WardrobeWriteError("Photo work was removed or changed. Manage this garment's photos or finish without a photo; it will not be attached twice.") }
            try photos.acceptDraft(entryID)
        } else {
            if !photos.drafts.contains(where: { $0.id == entryID }) {
                let bytes = try await drafts.importBytes(entryID)
                guard drafts.items.first(where: { $0.id == entryID })?.updatedAt == entry.updatedAt, !writes.contains(current.id) else { throw WardrobeWriteError("The import changed. Review it again.") }
                try photos.saveDraft(id: entryID, garment: current, retained: current.mediaIDs ?? [], photos: [WardrobePreparedPhoto(id: UUID(uuidString: entryID)!, original: bytes, chosen: bytes)])
            }
            guard let photoDraft = photos.drafts.first(where: { $0.id == entryID }), photoDraft.garment.id == current.id, photoDraft.photos.count == 1 else { throw WardrobeWriteError("Review the stored photo draft first.") }
            entry.importMediaID = photoDraft.photos[0].chosen.id
            try drafts.put(entry) // Persist the media identity before accepting an upload.
            try photos.acceptDraft(entryID)
        }
        Task { await sync() }
    }
    func finishImport(_ entryID: String) async throws {
        guard isCurrentOwner else { throw WardrobeWriteError("Sign in before finishing this import.") }
        guard let entry = drafts.items.first(where: { $0.id == entryID }), let mediaID = entry.importMediaID else { throw WardrobeWriteError("Attach the photo, or explicitly finish without it.") }
        guard try !entry.hasImportEdits() else { throw WardrobeWriteError("Review later garment edits in Pending saves before finishing.") }
        let current = try await importGarment(entry.entityID)
        guard drafts.items.first(where: { $0.id == entryID })?.updatedAt == entry.updatedAt,
              (current.mediaIDs ?? []).contains(mediaID), !writes.contains(current.id), !photos.contains(current.id), !photos.drafts.contains(where: { $0.id == entryID }) else { throw WardrobeWriteError("Wait for the photo attachment to be acknowledged. Pending saves shows any errors.") }
        try drafts.remove(entryID)
    }
}
