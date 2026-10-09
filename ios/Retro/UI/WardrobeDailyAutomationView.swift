import SwiftUI

struct WardrobeDailyAutomationView: View {
    let store: WardrobeStore
    @Environment(\.scenePhase) private var phase
    @State private var read = WardrobeRead<WardrobeDailySettingsResult>()
    @State private var edited: WardrobeDailySettings?
    @State private var problem: String?
    private var assistant: WardrobeAssistant { store.assistant }
    private var saved: WardrobeDailySettings? { read.value?.settings }
    private var editable: Bool { saved != nil && !read.loading && !read.cached && store.isCurrentOwner && !store.writes.contains(WardrobeDailySettings.identity) && !assistant.running }
    private var unchanged: Bool { edited == saved }

    var body: some View {
        Form {
            Section {
                Text("Your agent can generate choices while your phone is asleep. Save the settings, then apply them to the agent. Delivery uses a connected service you choose.").font(.footnote)
                WardrobeReadStatus(state: read) { await load() }
                if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                if store.writes.contains(WardrobeDailySettings.identity) { Text("Daily settings have a pending save. Resolve it in Pending saves before applying a schedule.").font(.footnote) }
            }
            if let edited {
                Section("Daily generation") {
                    Toggle("Enable daily generation", isOn: binding(\.enabled)).disabled(!editable)
                    Picker("Generate for", selection: binding(\.mode)) {
                        Text("This morning").tag("morning")
                        Text("Tomorrow, the evening before").tag("previous_evening")
                    }.disabled(!editable)
                    Picker("Hour", selection: binding(\.hour)) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }.disabled(!editable)
                    Picker("Minute", selection: binding(\.minute)) { ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }.disabled(!editable)
                    TextField("IANA time zone", text: binding(\.time_zone)).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(!editable)
                    Button("Use this device's time zone") { self.edited?.time_zone = TimeZone.current.identifier }.frame(minHeight: 44).disabled(!editable)
                    Text("Uses the saved time zone, including daylight saving changes. It does not move automatically when you travel. A skipped local time may have no firing; Today still generates choices on open.").font(.footnote)
                }
                Section("Optional delivery") {
                    TextField("Connected service and recipient", text: binding(\.delivery_target), axis: .vertical).lineLimit(2...4).disabled(!editable)
                    Text("Leave empty to generate only. Otherwise name the connected destination explicitly, such as your personal reminders list. The agent must find a matching sender. A delivery claim with an unknown outcome is kept for review and never automatically resent.").font(.footnote)
                    Text("This uses your agent's existing permissions. Applying these settings authorizes recurring generation and the selected delivery; it does not configure iPhone push notifications.").font(.footnote)
                }
                Section {
                    Button("Save daily settings", action: save).frame(minHeight: 44).disabled(!editable || unchanged)
                    Button(edited.enabled ? "Apply saved schedule to agent" : "Pause agent schedule") { act(apply: true) }.frame(minHeight: 44).disabled(!editable || !unchanged)
                    Button("Check agent schedule") { act(apply: false) }.frame(minHeight: 44).disabled(!editable || !unchanged)
                    Text("Saving alone changes the desired settings. Apply and check use the same named Temporal wake. Disabling saved settings blocks new generation and delivery claims even if pausing the wake is interrupted. Existing sends cannot be recalled.").font(.footnote)
                    Text("Stopping an apply attempt may leave the schedule active. Check or pause the saved schedule after recovery.").font(.footnote)
                }
            }
            if let receipt = assistant.dailyWake, receipt.settingsVersion == saved?.version {
                Section("Inspected agent schedule") {
                    LabeledContent("State", value: WardrobeVocabulary.title(receipt.state))
                    if let next = receipt.nextFire { LabeledContent("Next firing", value: next.formatted(date: .abbreviated, time: .shortened)) }
                    Text("Inspected \(receipt.readAt.formatted(date: .abbreviated, time: .shortened)). This is a snapshot; check again for current status.").font(.footnote)
                    DisclosureGroup("Source") { Text(receipt.wakeID).textSelection(.enabled); Text(receipt.sourceID).font(.caption).textSelection(.enabled) }
                }
            }
            if assistant.running { Section { ProgressView(assistant.status); Button("Stop this attempt", role: .destructive) { assistant.pause() }.frame(minHeight: 44) } }
            if let message = assistant.problem { Section { Text(message).foregroundStyle(Tok.stamp) } }
            if let storageProblem = assistant.requests.storageProblem { Section { Text(storageProblem).foregroundStyle(Tok.stamp) } }
            if let saved {
                ForEach(assistant.requests.items.filter { item in
                    item.query == (try? saved.agentQuery(apply: true, owner: assistant.requests.owner))
                        || item.query == (try? saved.agentQuery(apply: false, owner: assistant.requests.owner))
                }.reversed()) { item in
                    Section {
                        Button("Review original schedule request · " + item.statusText) {
                            let apply = item.query == (try? saved.agentQuery(apply: true, owner: assistant.requests.owner))
                            act(apply: apply, requestID: item.id)
                        }.frame(minHeight: 44).disabled(!editable || !unchanged || item.cancellationRequested)
                    }
                    WardrobeAgentRequestSection(assistant: assistant, item: item)
                }
            }
        }
        .navigationTitle("Daily automation")
        .task(id: store.changes) { await load() }
        .onChange(of: phase) { _, value in if value != .active { assistant.pause() } }
        .onDisappear { assistant.pause(); assistant.clearDailyWake() }
    }
    private func binding<Value>(_ key: WritableKeyPath<WardrobeDailySettings, Value>) -> Binding<Value> {
        Binding(get: { edited![keyPath: key] }, set: { edited?[keyPath: key] = $0 })
    }
    private func load() async {
        let unsaved = edited != nil && edited != saved
        read.loading = true; problem = nil
        let next: WardrobeRead<WardrobeDailySettingsResult> = await store.read("wardrobe_daily_settings_get", input: WardrobeEmpty())
        guard store.isCurrentOwner, !Task.isCancelled else { return }
        do {
            if let settings = next.value?.settings { try settings.validate() }
            read = next
            if !unsaved { edited = next.value?.settings }
        } catch { read = WardrobeRead(problem: error.localizedDescription); edited = nil }
    }
    private func save() {
        guard editable, let edited else { return }
        do {
            var fields = WardrobeDraftValidation.edit(id: edited.id, version: edited.version)
            fields["patch"] = try edited.fields()
            try store.submit("wardrobe_daily_settings_update", entity: edited.id, title: "Daily automation", fields: fields)
            self.edited = saved
            assistant.clearDailyWake()
        } catch { problem = error.localizedDescription }
    }
    private func act(apply: Bool, requestID: String? = nil) {
        guard editable, unchanged, let saved else { return }
        problem = nil
        assistant.checkDailyWake(saved, apply: apply, current: { store.isCurrentOwner && !store.writes.contains(saved.id) && self.saved == saved && self.edited == saved }, requestID: requestID)
    }
}

struct WardrobeScheduledChoicesView: View {
    let store: WardrobeStore
    let day: String
    let refresh: Int
    @State private var read = WardrobeRead<WardrobeDailyRunResult>()
    @State private var reviewing = false
    @State private var problem: String?
    @State private var seed: WardrobeOutfitSeed?
    @State private var task: Task<Void, Never>?
    @State private var zone = TimeZone.current.identifier
    private var input: WardrobeDailyReadInput { .init(day: day, time_zone: zone) }
    private var loadID: String { "\(day):\(TimeZone.current.identifier):\(refresh):\(store.changes)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink("Daily automation") { WardrobeDailyAutomationView(store: store) }.frame(minHeight: 44)
            WardrobeReadStatus(state: read) { await load() }
            if let run = read.value?.run {
                Text("Agent-generated choices").font(.headline)
                Text("\(run.day) · \(run.time_zone) · settings version \(run.settings_version)").font(.footnote)
                Text("Generated earlier. Review checks current pieces and preferences; your selected plan and actual wears are unchanged.").font(.footnote)
                if let generated = GatewayAgentResult.date(run.suggestions.generatedAt) { Text(generated.formatted(date: .abbreviated, time: .shortened)).font(.caption) }
                if let delivery = run.delivery {
                    Text(delivery.status == "sent" ? "Agent-recorded delivery receipt · " + delivery.target : "Delivery reserved; outcome not confirmed · " + delivery.target).font(.footnote)
                    if delivery.status == "claimed" { Text("Check the connected service before taking further action. This attempt is never automatically resent.").font(.footnote) }
                    if !delivery.receipt.isEmpty { DisclosureGroup("Agent-recorded receipt") { Text(delivery.receipt).textSelection(.enabled); Text(delivery.source).font(.caption).textSelection(.enabled) } }
                }
                ForEach(Array(run.suggestions.items.enumerated()), id: \.element.id) { index, option in
                    DisclosureGroup("Scheduled option \(index + 1)") {
                        ForEach(option.items, id: \.garmentID) { Text(($0.name ?? "Piece") + " · " + WardrobeVocabulary.title($0.role)) }
                        ForEach(Array(option.reasons.enumerated()), id: \.offset) { _, reason in Text(reason).font(.footnote) }
                        if !option.missingRoles.isEmpty { Text("Missing: " + option.missingRoles.map(WardrobeVocabulary.title).joined(separator: ", ")).font(.footnote) }
                        Button("Recheck and review as a plan") { review(option, run: run) }.frame(minHeight: 44).disabled(reviewing || read.loading || (GatewayAgentResult.date(run.expires_at) ?? .distantPast) <= Date())
                    }
                }
                if run.suggestions.items.isEmpty { Text(run.suggestions.noResultReason ?? "No eligible scheduled choices. Use fresh choices or compose manually.").font(.footnote) }
                if (GatewayAgentResult.date(run.expires_at) ?? .distantPast) <= Date() { Text("This snapshot expired. Use the fresh choices below.").font(.footnote) }
            }
            if reviewing { ProgressView("Checking current pieces and preferences") }
            if let problem { Text(problem).foregroundStyle(Tok.stamp).font(.footnote) }
        }
        .task(id: loadID) { await load() }
        .sheet(item: $seed) { WardrobeOutfitEditor(store: store, seed: $0.draft) }
        .onChange(of: loadID) { _, _ in task?.cancel() }
        .onDisappear { task?.cancel() }
    }
    private func load() async {
        let id = loadID
        read.loading = true; problem = nil
        let settings: WardrobeRead<WardrobeDailySettingsResult> = await store.read("wardrobe_daily_settings_get", input: WardrobeEmpty())
        guard id == loadID, !Task.isCancelled, store.isCurrentOwner else { return }
        do { guard let value = settings.value?.settings else { throw WardrobeWriteError(settings.problem ?? "Load daily settings first.") }; try value.validate(); zone = value.time_zone }
        catch { read = WardrobeRead(problem: error.localizedDescription); return }
        let request = input
        let next: WardrobeRead<WardrobeDailyRunResult> = await store.read("wardrobe_daily_get", input: request)
        guard id == loadID, !Task.isCancelled, store.isCurrentOwner else { return }
        do { try next.value?.run?.validate(request); read = next }
        catch { read = WardrobeRead(problem: error.localizedDescription) }
    }
    private func review(_ option: WardrobeSuggestion, run: WardrobeDailyRun) {
        guard !reviewing else { return }
        let id = loadID; reviewing = true; problem = nil
        task = Task {
            defer { reviewing = false }
            do {
                try run.validate(input)
                guard (GatewayAgentResult.date(run.expires_at) ?? .distantPast) > Date() else { throw WardrobeWriteError("This scheduled snapshot expired. Use fresh choices.") }
                let draft = try await store.reviewSuggestion(option, query: run.query)
                guard id == loadID, !Task.isCancelled, store.isCurrentOwner else { return }
                seed = WardrobeOutfitSeed(draft: draft)
            } catch { if id == loadID, !Task.isCancelled, store.isCurrentOwner { problem = error.localizedDescription } }
        }
    }
}
