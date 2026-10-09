import SwiftUI
import AVFoundation

struct WardrobeVoiceInput: View {
    let store: WardrobeStore
    @Binding var text: String
    let byteLimit: Int
    @Environment(\.scenePhase) private var phase
    @State private var speech = WardrobeSpeech()
    @State private var baseline = ""
    @State private var task: Task<Void, Never>?
    @State private var problem: String?
    var body: some View {
        Group {
            Button(speech.recording ? "Stop recording" : speech.busy ? "Cancel recording" : "Record a description", systemImage: speech.recording ? "stop.circle" : "mic") {
                if speech.busy { task?.cancel(); speech.stop() }
                else {
                    baseline = text; problem = nil
                    task = Task { await speech.start(byteLimit: byteLimit, stillOwner: { store.isCurrentOwner }) }
                }
            }.frame(minHeight: 44)
            Text("Optional, on-device speech only. Recording stops after 30 seconds. Review the transcript before using it; typed input always works.").font(.footnote)
            if !speech.transcript.isEmpty {
                TextField("Transcript — check for errors", text: Binding(get: { speech.transcript }, set: { speech.transcript = $0 }), axis: .vertical).lineLimit(3...6).disabled(speech.busy)
                Button("Use reviewed transcript") {
                    do {
                        text = try WardrobeSpeech.reviewed(speech.transcript, baseline: baseline, current: text, owner: store.isCurrentOwner, byteLimit: byteLimit)
                        speech.stop(clear: true)
                    } catch { problem = error.localizedDescription }
                }.frame(minHeight: 44).disabled(speech.busy)
                Button("Discard transcript") { task?.cancel(); speech.stop(clear: true); problem = nil }.frame(minHeight: 44)
            }
            if let message = problem ?? speech.problem { Text(message).font(.footnote).foregroundStyle(Tok.stamp) }
        }
        .onChange(of: text) { _, _ in task?.cancel(); speech.stop(clear: true); problem = nil }
        .onChange(of: phase) { _, value in
            if value == .background || (value == .inactive && speech.recording) { task?.cancel(); speech.stop(clear: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in task?.cancel(); speech.stop() }
        .onDisappear { task?.cancel(); speech.stop(clear: true) }
    }
}
