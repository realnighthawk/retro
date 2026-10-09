import SwiftUI

struct WardrobeCandidateAssistanceView: View {
    let store: WardrobeStore
    let context: WardrobeCandidateContext
    let current: () -> Bool
    let onSwap: (WardrobeSuggestQuery, [WardrobeSelection]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var question = "Compare these choices for me."
    @State private var connected = false
    @State private var acceptLimitations = false
    @State private var busy = false
    @State private var problem: String?
    @State private var task: Task<Void, Never>?
    @State private var seed: WardrobeOutfitSeed?
    @State private var location = ""
    @State private var manualWarmth = ""
    @State private var manualOccasion = ""
    private var contextRequest: WardrobeOutfitContextRequest { WardrobeOutfitContextRequest(day: context.query.day, timeZone: context.timeZone, location: location.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var connectedFacts: WardrobeOutfitContext? { assistant.outfitContext?.request == contextRequest ? assistant.outfitContext : nil }
    private var assistant: WardrobeAssistant { store.assistant }
    private var sourceCurrent: Bool {
        current() && store.isCurrentOwner && store.changes == context.revision && TimeZone.current.identifier == context.timeZone
    }
    private var advice: WardrobeCandidateAdvice? {
        guard let advice = assistant.candidateAdvice, advice.context.query == context.query,
              advice.context.revision == context.revision, advice.context.result.items.map(\.id) == context.result.items.map(\.id) else { return nil }
        return advice
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Ask about these choices") {
                    Text("For \(context.query.day) · \(context.timeZone)").font(.footnote)
                    TextField("Compare options, or swap the shoes in option 2", text: $question, axis: .vertical).lineLimit(3...6).disabled(assistant.running || busy)
                    if !assistant.running && !busy { WardrobeVoiceInput(store: store, text: $question, byteLimit: 1200) }
                    Toggle("Allow connected help", isOn: $connected).disabled(assistant.running || busy)
                    Button("Ask on this device") {
                        acceptLimitations = false; problem = nil
                        let request = contextRequest
                        assistant.askChoices(question, context: context, store: store, connected: connected, outfitContextRequest: connected ? request : nil,
                            current: { sourceCurrent && contextRequest == request })
                    }.frame(minHeight: 44).disabled(assistant.running || busy || !sourceCurrent || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || GarmentAssistance.unavailableReason != nil)
                    if let reason = GarmentAssistance.unavailableReason { Text(reason + " Use Compare, Describe an outfit or the manual swap controls.").font(.footnote).foregroundStyle(.secondary) }
                    if !sourceCurrent { Text("The date, request or saved records changed. Close this sheet and refresh choices.").font(.footnote) }
                }
                Section {
                    Text("Apple's model reads fresh engine choices on this device. Optional connected help retrieves source-backed weather/calendar/travel through your agent's existing tool permissions. Generic agent advice stays separate. Review context and any proposed request change; missing facts use manual controls.").font(.footnote)
                }
                Section("Context for this day") {
                    TextField("Weather location (optional city or place)", text: $location).disabled(assistant.running || busy)
                    Text("Enter a location for weather; it is never inferred. Calendar/travel reads use the selected date and time zone. Enabling connected help sends this scope and any delegated question to your agent.").font(.footnote)
                    Button("Retrieve connected context") {
                        let request = contextRequest; problem = nil
                        assistant.fetchOutfitContext(request, current: { sourceCurrent && contextRequest == request })
                    }.frame(minHeight: 44).disabled(!connected || assistant.running || busy || !sourceCurrent)
                    ForEach(assistant.requests.items.filter { $0.query == (try? contextRequest.agentQuery()) && !$0.cancellationRequested }) { item in
                        Button("Review saved context · " + item.statusText) {
                            let request = contextRequest
                            assistant.fetchOutfitContext(request, current: { sourceCurrent && contextRequest == request }, requestID: item.id)
                        }.frame(minHeight: 44).disabled(!connected || assistant.running || busy || !sourceCurrent)
                    }
                }
                if let connectedFacts {
                    WardrobeOutfitContextSections(facts: connectedFacts)
                    Section("Adjust the request manually") {
                        TextField("Occasion", text: $manualOccasion)
                        Picker("Warmth", selection: $manualWarmth) {
                            Text("Any warmth").tag("")
                            ForEach(["light", "mid", "warm"], id: \.self) { Text(WardrobeVocabulary.title($0)).tag($0) }
                        }
                        Button("Review adjusted choices") { refine(connectedFacts, warmth: manualWarmth, occasion: manualOccasion) }
                            .frame(minHeight: 44).disabled(busy || assistant.running || !sourceCurrent)
                        Text("Use the source context to choose these fields. Rain does not establish waterproof garments or care safety. Other locks and exclusions stay in place.").font(.footnote)
                    }
                }
                if assistant.running {
                    Section {
                        ProgressView(assistant.status)
                        Button("Stop this attempt", role: .destructive) { assistant.pause() }.frame(minHeight: 44)
                    }
                }
                if let message = problem ?? assistant.problem { Section { Text(message).foregroundStyle(Tok.stamp).textSelection(.enabled) } }
                if let advice {
                    Section("On-device interpretation") {
                        Text(advice.proposal.explanation).textSelection(.enabled)
                        Text("Model commentary. Refer to the engine's recorded reasons below; no plan, wear or swap has been saved.").font(.footnote).foregroundStyle(.secondary)
                        ForEach(Array(advice.proposal.unhandled.enumerated()), id: \.offset) { _, condition in Text("Not applied: " + condition).font(.footnote) }
                        if !advice.proposal.unhandled.isEmpty, advice.proposal.intent != .unsupported {
                            Toggle("Continue without these conditions", isOn: $acceptLimitations)
                        }
                        if let candidate = advice.proposal.candidate, let option = advice.context.candidate(candidate) {
                            Text("Proposed option \(advice.context.result.items.firstIndex(where: { $0.id == option.id })! + 1)").font(.headline)
                            if let piece = advice.proposal.piece, let selection = advice.context.piece(piece, in: option) {
                                Text("Swap \(selection.name) · \(WardrobeVocabulary.title(selection.role)). Keep the other pieces locked and exclude this piece.")
                            }
                            Button(advice.proposal.intent == .swap ? "Review swap in Suggestions" : "Review this outfit as a plan") { review(advice) }
                                .frame(minHeight: 44).disabled(busy || assistant.running || !sourceCurrent || (!advice.proposal.unhandled.isEmpty && !acceptLimitations))
                        }
                        if advice.proposal.intent == .refine, let facts = advice.connectedContext {
                            if let warmth = advice.proposal.warmth { Text("Proposed warmth: " + WardrobeVocabulary.title(warmth)) }
                            if let occasion = advice.proposal.occasion { Text("Proposed occasion: " + occasion) }
                            Text("Context used: " + advice.proposal.contextEvidence.joined(separator: ", ")).font(.footnote)
                            Button("Review adjusted choices") { refine(facts, warmth: advice.proposal.warmth, occasion: advice.proposal.occasion, proposal: advice.proposal) }
                                .frame(minHeight: 44).disabled(busy || assistant.running || !sourceCurrent || (!advice.proposal.unhandled.isEmpty && !acceptLimitations))
                        }
                        if let date = GatewayAgentResult.date(advice.context.result.generatedAt) { Text("Engine facts read \(date.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary) }
                    }
                    Section("Engine evidence used") {
                        ForEach(Array(advice.proposal.evidence.enumerated()), id: \.offset) { _, ref in
                            if let option = advice.context.candidate(ref.candidate) { Text(option.reasons[ref.reason - 1]).font(.footnote) }
                        }
                    }
                }
                if busy { Section { ProgressView("Refreshing the proposal for review") } }
                let facts = advice?.context ?? context
                Section("Ranking sources") {
                    LabeledContent("Wardrobe settings version", value: String(facts.query.expectedPreferencesVersion!))
                    LabeledContent("Rated-wear samples", value: String(facts.result.feedbackSamples ?? 0))
                    Text("Rating evidence covers up to 2000 version-matched confirmed wears through the selected date. Choices cover a bounded engine search; pending saves are excluded.").font(.footnote)
                    ForEach(Array((facts.result.warnings ?? []).enumerated()), id: \.offset) { _, warning in Text(warning).font(.footnote) }
                }
                ForEach(Array(facts.result.items.enumerated()), id: \.element.id) { index, option in
                    Section("Option \(index + 1) · engine facts") {
                        ForEach(option.items, id: \.garmentID) { item in
                            Text((item.name ?? "Piece") + " · " + WardrobeVocabulary.title(item.role) + (facts.query.requiredIDs.contains(item.garmentID) ? " · Locked" : ""))
                        }
                        LabeledContent("Ranking score", value: String(option.score ?? 0))
                        if !option.missingRoles.isEmpty { Text("Missing: " + option.missingRoles.map(WardrobeVocabulary.title).joined(separator: ", ")).font(.footnote) }
                        DisclosureGroup("All engine reasons") { ForEach(Array(option.reasons.enumerated()), id: \.offset) { _, reason in Text(reason).font(.footnote) } }
                    }
                }
                if facts.result.items.isEmpty { Section { Text(facts.result.noResultReason ?? "No eligible choices. Review the request or compose manually.") } }
                if let storageProblem = assistant.requests.storageProblem { Section("Saved requests") { Text(storageProblem) } }
                ForEach(assistant.requests.items.reversed()) { WardrobeAgentRequestSection(assistant: assistant, item: $0) }
            }
            .navigationTitle("Outfit help").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { stop(); dismiss() } } }
            .sheet(item: $seed) { WardrobeOutfitEditor(store: store, seed: $0.draft) }
        }
        .onChange(of: question) { _, _ in stop(); assistant.clearCandidateAdvice(); acceptLimitations = false }
        .onChange(of: location) { _, _ in stop(); assistant.clearCandidateAdvice(); assistant.clearOutfitContext() }
        .onChange(of: sourceCurrent) { _, valid in if !valid { stop() } }
        .onChange(of: phase) { _, value in if value != .active { stop() } }
        .onAppear { assistant.clearCandidateAdvice(); assistant.clearOutfitContext(); manualWarmth = context.query.warmth; manualOccasion = context.query.occasion }
        .onDisappear { stop(); assistant.clearCandidateAdvice(); assistant.clearOutfitContext() }
    }
    private func stop() { task?.cancel(); assistant.pause() }
    private func review(_ advice: WardrobeCandidateAdvice) {
        guard sourceCurrent, !busy, !assistant.running, advice.proposal.intent != .unsupported,
              advice.proposal.unhandled.isEmpty || acceptLimitations else { return }
        busy = true; problem = nil
        task = Task {
            defer { busy = false }
            do {
                try advice.proposal.validate(advice.context, connected: advice.connectedContext)
                if advice.proposal.intent == .swap {
                    let fresh = try await store.refreshCandidateContext(advice.context)
                    let query = try advice.proposal.swapQuery(fresh)
                    guard !Task.isCancelled, sourceCurrent else { return }
                    let pieces = fresh.candidate(advice.proposal.candidate!)!.items.map { WardrobeSelection(id: $0.garmentID, name: $0.name ?? "Piece", role: $0.role) }
                    onSwap(query, pieces); dismiss()
                } else if let candidate = advice.proposal.candidate, let option = advice.context.candidate(candidate) {
                    let draft = try await store.reviewSuggestion(option, query: advice.context.query)
                    guard !Task.isCancelled, sourceCurrent else { return }
                    seed = WardrobeOutfitSeed(draft: draft)
                }
            } catch { if !Task.isCancelled, sourceCurrent { problem = error.localizedDescription } }
        }
    }
    private func refine(_ facts: WardrobeOutfitContext, warmth: String?, occasion: String?, proposal: WardrobeCandidateProposal? = nil) {
        guard sourceCurrent, !busy, !assistant.running, proposal == nil || proposal!.unhandled.isEmpty || acceptLimitations else { return }
        busy = true; problem = nil
        let request = contextRequest
        task = Task {
            defer { busy = false }
            do {
                try facts.validate(request)
                if let proposal { try proposal.validate(context, connected: facts) }
                let fresh = try await store.refreshCandidateContext(context)
                let query = try facts.refining(fresh.query, warmth: warmth, occasion: occasion)
                guard !Task.isCancelled, sourceCurrent, contextRequest == request else { return }
                let pieces = fresh.result.items.flatMap(\.items).map { WardrobeSelection(id: $0.garmentID, name: $0.name ?? "Piece", role: $0.role) }
                onSwap(query, pieces); dismiss()
            } catch { if !Task.isCancelled, sourceCurrent { problem = error.localizedDescription } }
        }
    }
}
