import SwiftUI

struct WardrobeLaundryPlanningView: View {
    let store: WardrobeStore
    let context: WardrobeLaundryAssistanceContext
    let current: () -> Bool
    let onApply: (WardrobeLaundryDraft, WardrobeLaundryPreview) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var question = "Prioritize pieces in my upcoming outfits and suggest compatible laundry batches."
    @State private var needBy: String
    @State private var connected = false
    @State private var acceptedLimitations = false
    @State private var busy = false
    @State private var problem: String?
    @State private var task: Task<Void, Never>?
    init(store: WardrobeStore, context: WardrobeLaundryAssistanceContext, current: @escaping () -> Bool,
         onApply: @escaping (WardrobeLaundryDraft, WardrobeLaundryPreview) throws -> Void) {
        self.store = store; self.context = context; self.current = current; self.onApply = onApply
        _needBy = State(initialValue: context.draft.day)
    }
    private var assistant: WardrobeAssistant { store.assistant }
    private var scope: WardrobeLaundryPlanningScope {
        .init(from: WardrobeLaundryPlanningScope.day(Date(), zone: TimeZone(identifier: context.draft.time_zone) ?? .current), need_by: needBy, time_zone: context.draft.time_zone)
    }
    private var sourceCurrent: Bool { current() && store.isCurrentOwner && store.changes == context.revision }
    private var advice: WardrobeLaundryPlanningAdvice? {
        guard let value = assistant.laundryAdvice, value.context.scope == scope, value.context.preview.program == context.draft.program,
              value.context.revision == context.revision else { return nil }; return value
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Plan around wardrobe needs") {
                    Text(context.draft.program.summary).font(.headline)
                    Text("Programme stays fixed. Need-by date covers today through the next 14 calendar dates in \(context.draft.time_zone).").font(.footnote)
                    DatePicker("Garments needed by", selection: needDate, displayedComponents: .date)
                        .environment(\.timeZone, TimeZone(identifier: context.draft.time_zone) ?? .current).disabled(assistant.running || busy)
                    TextField("Laundry planning request", text: $question, axis: .vertical).lineLimit(3...6).disabled(assistant.running || busy)
                    if !assistant.running && !busy { WardrobeVoiceInput(store: store, text: $question, byteLimit: 600) }
                    Toggle("Allow connected help", isOn: $connected).disabled(assistant.running || busy)
                    Text("Connected help sends the request and a small selection of piece/outfit details to your agent. Apple's model can also request calendar/travel context for the need-by day. Uses your agent's existing permissions; review any questions it presents.").font(.footnote)
                    Button("Plan on this device") { ask(onDevice: true) }.frame(minHeight: 44).disabled(!canAsk || GarmentAssistance.unavailableReason != nil)
                    Button("Ask connected planner") { ask(onDevice: false) }.frame(minHeight: 44).disabled(!canAsk || !connected)
                    if let reason = GarmentAssistance.unavailableReason { Text(reason + " Manual groups and the connected planner remain available.").font(.footnote).foregroundStyle(.secondary) }
                    if !sourceCurrent { Text("The laundry form or saved records changed. Reopen planning from the current form.").foregroundStyle(Tok.stamp) }
                }
                Section {
                    Text("Review one batch at a time. Proposals do not save or start loads. Existing laundry plans, machine capacity and wash/dry durations are not assessed; check existing loads before saving another. Dates cannot guarantee garments are dry and ready. Unknown or blocked care stays in the ordinary compatibility review.").font(.footnote)
                }
                if assistant.running {
                    Section { ProgressView(assistant.status); Button("Stop this attempt", role: .destructive) { stop() }.frame(minHeight: 44) }
                }
                if busy { Section { ProgressView("Refreshing sources for the reviewed batch") } }
                if let problem = problem ?? assistant.problem { Section { Text(problem).foregroundStyle(Tok.stamp).textSelection(.enabled) } }
                if let advice {
                    Section("Planning coverage") {
                        Text(assistant.answerOrigin ?? "Laundry proposal").font(.headline)
                        Text("\(advice.context.pieces.count) compatible pieces and \(advice.context.plans.count) same-zone saved outfits represented.").font(.footnote)
                        Text("One page of up to 20 planned outfits. \(advice.context.planCoverage == "first_page_partial" ? "More plans exist beyond this page." : "This date-range page is complete.") \(advice.context.omittedPlans) read plans and \(advice.context.omittedPieces) compatible pieces omitted from the model sample, including \(advice.context.otherZonePlans) plans in other time zones.").font(.footnote)
                        Text("\(advice.context.preview.blocked.count) garments need care review or a different programme. Other availability states and archived garments are outside this preview.").font(.footnote)
                        Text("Read \(GatewayAgentResult.date(advice.context.preview.generated_at)?.formatted(date: .abbreviated, time: .shortened) ?? advice.context.preview.generated_at)").font(.caption)
                    }
                    if let facts = advice.connected { WardrobeOutfitContextSections(facts: facts) }
                    if advice.proposal.batches.isEmpty { Section { Text("No supported batch proposed. Continue with manual groups.") } }
                    ForEach(Array(advice.proposal.batches.enumerated()), id: \.offset) { index, batch in
                        Section("Batch \(index + 1) · \(WardrobeVocabulary.title(advice.context.group(batch.group)!.colour_group))") {
                            Text("Planned \(batch.day) · \(advice.context.scope.time_zone)").font(.headline)
                            Text(batch.explanation).textSelection(.enabled)
                            Text("Model commentary; review the source facts below. No wash or ready-by assurance.").font(.footnote).foregroundStyle(.secondary)
                            ForEach(batch.pieces, id: \.self) { alias in
                                if let piece = advice.context.piece(alias) { Text(piece.name); Text("Reviewed garment version \(piece.version)").font(.caption) }
                            }
                            ForEach(batch.plans, id: \.self) { alias in
                                if let plan = advice.context.plan(alias) { Text("Need: \(plan.title) · \(plan.day) · \(plan.timeZone) · version \(plan.version)").font(.footnote) }
                            }
                            if !batch.context_evidence.isEmpty { Text("Connected facts used: " + batch.context_evidence.joined(separator: ", ")).font(.footnote) }
                            Button("Review this batch in the load form") { apply(index, advice: advice) }.frame(minHeight: 44)
                                .disabled(busy || assistant.running || !sourceCurrent || !advice.proposal.unhandled.isEmpty && !acceptedLimitations)
                        }
                    }
                    if !advice.proposal.unhandled.isEmpty {
                        Section("Conditions not applied") {
                            ForEach(Array(advice.proposal.unhandled.enumerated()), id: \.offset) { _, value in Text(value) }
                            Toggle("Continue with only the proposed batch", isOn: $acceptedLimitations).disabled(assistant.running || busy)
                        }
                    }
                }
                if let storage = assistant.requests.storageProblem { Section("Saved requests") { Text(storage) } }
                ForEach(assistant.requests.items.reversed()) { WardrobeAgentRequestSection(assistant: assistant, item: $0) }
            }.navigationTitle("Laundry planning").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { stop(); dismiss() } } }
        }
        .onAppear { assistant.clearLaundryAdvice(); assistant.clearOutfitContext() }
        .onChange(of: question) { _, _ in clear() }
        .onChange(of: needBy) { _, _ in clear() }
        .onChange(of: connected) { _, _ in clear() }
        .onChange(of: sourceCurrent) { _, valid in if !valid { clear() } }
        .onChange(of: phase) { _, value in if value != .active { clear() } }
        .onDisappear { clear() }
    }
    private var canAsk: Bool { sourceCurrent && !busy && !assistant.running && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var needDate: Binding<Date> {
        let zone = TimeZone(identifier: context.draft.time_zone) ?? .current
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone; f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        return Binding(get: { f.date(from: needBy) ?? Date() }, set: { needBy = WardrobeLaundryPlanningScope.day($0, zone: zone) })
    }
    private func stop() { task?.cancel(); assistant.pause() }
    private func clear() { stop(); assistant.clearLaundryAdvice(); assistant.clearOutfitContext(); acceptedLimitations = false }
    private func ask(onDevice: Bool) {
        problem = nil; acceptedLimitations = false
        let request = scope; let originalQuestion = question; let consent = connected
        assistant.askLaundry(question, program: context.draft.program, scope: request, store: store, connected: connected, onDevice: onDevice,
            current: { sourceCurrent && scope == request && question == originalQuestion && connected == consent })
    }
    private func apply(_ index: Int, advice: WardrobeLaundryPlanningAdvice) {
        guard !busy, !assistant.running, sourceCurrent else { return }
        busy = true; problem = nil
        let request = scope
        task = Task {
            defer { busy = false }
            do {
                try advice.proposal.validate(advice.context, connected: advice.connected)
                let fresh = try await store.laundryPlanningContext(program: context.draft.program, scope: request, revision: context.revision)
                let draft = try advice.proposal.reviewedBatch(index, context: advice.context, fresh: fresh, connected: advice.connected, acceptedLimitations: acceptedLimitations)
                try Task.checkCancellation(); guard sourceCurrent, scope == request else { throw CancellationError() }
                try store.checkLaundryPlanningPending(fresh); try onApply(draft, fresh.preview); dismiss()
            } catch { if !Task.isCancelled, sourceCurrent { problem = error.localizedDescription } }
        }
    }
}
