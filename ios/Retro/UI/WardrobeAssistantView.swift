import SwiftUI

struct WardrobeAssistantView: View {
    let assistant: WardrobeAssistant
    let day: String
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var connected = false
    private var unavailable: String? { GarmentAssistance.unavailableReason?.replacingOccurrences(of: "Manual entry still works.", with: "You can ask the connected agent below.") }
    private var cannotAsk: Bool { assistant.running || !assistant.requests.isCurrentOwner || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What would you like help with?", text: $question, axis: .vertical)
                        .lineLimit(3...8).disabled(assistant.running)
                    Text("For \(day) · \(TimeZone.current.identifier)").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Allow connected help", isOn: $connected).disabled(assistant.running)
                    Button("Ask Retro on this device") { assistant.ask(question, day: day, connected: connected) }
                        .frame(minHeight: 44).disabled(cannotAsk || unavailable != nil)
                    Button("Ask connected agent") { assistant.ask(question, day: day, connected: true, onDevice: false) }
                        .frame(minHeight: 44).disabled(cannotAsk)
                    if let unavailable { Text(unavailable).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Ask Retro") } footer: {
                    Text("Apple's model works on this device. Allowing connected help sends the question and delegated queries to your agent, which uses its existing tool permissions. Questions and approvals appear below. Each attempt has a 90-second limit.")
                }
                if assistant.running || !assistant.status.isEmpty || assistant.problem != nil {
                    Section {
                        if assistant.running {
                            ProgressView(assistant.status).accessibilityLabel(assistant.status)
                            Button("Stop this attempt", role: .destructive) { assistant.pause("Stopped on this device. Connected stop remains pending until confirmed.") }.frame(minHeight: 44)
                        } else { Text(assistant.status).foregroundStyle(.secondary) }
                        if let problem = assistant.problem { Text(problem).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                }
                if let answer = assistant.answer {
                    Section {
                        Text(answer).textSelection(.enabled)
                        if let time = assistant.factsRetrievedAt, let date = GatewayAgentResult.date(time) {
                            Text("Wardrobe facts read \(date.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
                        }
                    } header: { Text(assistant.answerOrigin ?? "Answer") } footer: {
                        Text("Review advice before acting. Use the wardrobe editing screens to review and save record changes.")
                    }
                }
                if let problem = assistant.requests.storageProblem { Section("Saved requests") { Text(problem) } }
                ForEach(assistant.requests.items.reversed()) { item in
                    WardrobeAgentRequestSection(assistant: assistant, item: item)
                }
            }
            .navigationTitle("Ask Retro").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { assistant.pause(); dismiss() } } }
        }
        .onDisappear { assistant.pause() }
    }
}

struct WardrobeAgentRequestSection: View {
    let assistant: WardrobeAssistant
    let item: WardrobeAgentRequest
    @State private var writtenAnswer = ""
    private var cannotAnswer: Bool { assistant.requests.sending || !assistant.requests.isCurrentOwner || (assistant.running && assistant.waitingRequestID != item.id) }

    var body: some View {
        Section {
            Text(item.statusText).font(.headline)
            Text("Started \(item.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
            DisclosureGroup("Original connected query") { Text(item.query).textSelection(.enabled) }
            if let problem = item.problem { Text(problem).foregroundStyle(.secondary) }
            if let input = item.pendingInput {
                Text(input.kind == "permission" ? "Approval requested" : "Your answer is needed").font(.headline)
                Text(input.prompt).textSelection(.enabled)
                ForEach(input.options) { option in
                    Button {
                        assistant.answerRequest(item.id, response: GatewayAgentResponse(request_id: input.request_id, selected_option_id: option.id))
                    } label: { Text(option.label).frame(minHeight: 44, alignment: .leading) }
                    .disabled(cannotAnswer)
                }
                if input.allow_free_text {
                    TextField("Your answer", text: $writtenAnswer, axis: .vertical).lineLimit(2...8)
                    Button("Send my answer") {
                        assistant.answerRequest(item.id, response: GatewayAgentResponse(request_id: input.request_id, free_text: writtenAnswer))
                    }.frame(minHeight: 44)
                        .disabled(cannotAnswer || writtenAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || writtenAnswer.utf8.count > 4000)
                }
            }
            if let result = item.latest {
                if let answer = result.answer { DisclosureGroup("Connected answer") { Text(answer).textSelection(.enabled) } }
                if let date = GatewayAgentResult.date(result.retrieved_at) {
                    Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
                }
                if result.status.terminal {
                    Text(result.truncated ? "Partial result. Some answer or evidence was omitted." : "Evidence covers recent top-level tool calls only.").font(.footnote).foregroundStyle(.secondary)
                    if let sources = result.sources, !sources.isEmpty {
                        DisclosureGroup("Connected evidence") {
                            ForEach(sources, id: \.tool_call_id) { source in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(source.tool_name) · \(source.status)")
                                    Text(source.tool_call_id).font(.caption).textSelection(.enabled)
                                    if let date = GatewayAgentResult.date(source.started_at) { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                                    if source.truncated == true { Text("Tool result omitted").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
            }
            if !item.terminal {
                Button(item.cancellationRequested ? "Check stop status" : "Check saved request") { assistant.checkRequest(item.id) }
                    .frame(minHeight: 44).disabled(assistant.running || assistant.requests.sending || !assistant.requests.isCurrentOwner)
                if !item.cancellationRequested {
                    Button("Stop connected request", role: .destructive) { assistant.stopRequest(item.id) }.frame(minHeight: 44)
                }
            }
        } header: { Text("Connected request") }
        .onChange(of: item.pendingInput?.request_id) { _, _ in writtenAnswer = "" }
    }
}
