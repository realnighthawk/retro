import SwiftUI

struct WardrobeDayChoiceRequest: Identifiable {
    let id = UUID()
    let day: String
    let outfitID: String?
    init(day: String, outfitID: String?) { self.day = day; self.outfitID = outfitID }
    init(request: WardrobePending) throws {
        guard request.operation == "wardrobe_day_selection_update", let fields = try JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              fields["id"] as? String == request.entity, fields["idempotency_key"] as? String == request.id,
              let day = fields["day"] as? String, WardrobeDraftValidation.date(day) != nil else { throw WardrobeWriteError("The original daily selection could not be opened.") }
        self.day = day
        if fields["outfit_id"] is NSNull { outfitID = nil }
        else if let value = fields["outfit_id"] as? String, WardrobeMediaPath.path(id: value) != nil { outfitID = value }
        else { throw WardrobeWriteError("Keep the original request; its outfit identity could not be opened.") }
    }
}
struct WardrobeDaySelectionView: View {
    let store: WardrobeStore
    let day: String
    let outfitID: String?
    var pending: WardrobePending?
    @Environment(\.dismiss) private var dismiss
    @State private var selection: WardrobeDaySelection?
    @State private var outfit: WardrobeOutfit?
    @State private var loading = false
    @State private var problem: String?
    @State private var saved = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Selected for this day") {
                    Text(day)
                    Text(selection?.outfit?.title ?? "No saved selection")
                    if let choice = selection?.outfit { Text(choice.items.map { $0.snapshot?.name ?? "Garment" }.joined(separator: ", ")).font(.footnote) }
                    if let issue = selection?.problem { Text(issue).font(.footnote) }
                }
                Section(outfitID == nil ? "Clear selection" : "Choose saved plan") {
                    if let outfit {
                        Text(outfit.title)
                        ForEach(outfit.items) { item in Text(item.snapshot?.name ?? "Garment") }
                        Text("\(outfit.day) · \(outfit.timeZone)").font(.footnote)
                    }
                    Text(outfitID == nil ? "Clearing keeps the outfit and its history." : "This keeps your chosen plan visible across refreshes. Record wear separately after reviewing what you actually wear.").font(.footnote)
                    if pending != nil { Text("This replaces the rejected request with a new save using the versions reviewed here.").font(.footnote) }
                    if loading { ProgressView("Refreshing selection and plan") }
                    if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                    Button("Refresh before choosing") { Task { await load() } }.frame(minHeight: 44).disabled(loading || saved)
                }
            }.navigationTitle(outfitID == nil ? "Clear daily choice" : "Choose daily plan").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(outfitID == nil ? "Clear" : "Choose", action: save).disabled(loading || selection == nil || (outfitID != nil && outfit == nil) || saved) }
                }
        }.task { await load() }
    }
    private func load() async {
        guard !loading else { return }
        loading = true; selection = nil; outfit = nil; problem = nil
        defer { loading = false }
        do {
            var reviewedOutfit: WardrobeOutfit?
            let read: WardrobeRead<WardrobeDay> = await store.read("wardrobe_day_get", input: WardrobeDayQuery(day: day))
            guard !read.cached, let value = read.value?.selection, value.day == day else { throw WardrobeWriteError(read.problem ?? "Daily selections are unavailable. Try again when the service is ready.") }
            try value.validate()
            if let pending { guard pending.entity == value.id else { throw WardrobeWriteError("The pending selection does not match this date.") } }
            if let outfitID {
                guard !store.writes.contains(outfitID) else { throw WardrobeWriteError("Resolve the plan's pending save before choosing it.") }
                let read: WardrobeRead<WardrobeOutfitResult> = await store.read("outfits_get", input: WardrobeID(id: outfitID))
                guard !read.cached, let current = read.value?.outfit, current.id == outfitID else { throw WardrobeWriteError(read.problem ?? "A fresh saved plan is needed.") }
                _ = try value.fields(choosing: current)
                reviewedOutfit = current
            } else { _ = try value.fields(choosing: nil) }
            try Task.checkCancellation(); guard store.isCurrentOwner else { return }
            selection = value; outfit = reviewedOutfit
        } catch { if store.isCurrentOwner, !Task.isCancelled { problem = error.localizedDescription } }
    }
    private func save() {
        guard let selection, !saved else { return }
        do {
            guard outfit.map({ !store.writes.contains($0.id) }) ?? true else { throw WardrobeWriteError("Resolve the plan's pending save before choosing it.") }
            let fields = try selection.fields(choosing: outfit)
            if let pending {
                try store.writes.replaceRejected(pending.id, operation: "wardrobe_day_selection_update", fields: fields)
                Task { await store.sync() }
            } else { try store.submit("wardrobe_day_selection_update", entity: selection.id, title: "Daily choice · \(day)", fields: fields, context: outfit?.title ?? "Clear selection") }
            saved = true; dismiss()
        } catch { problem = error.localizedDescription }
    }
}
