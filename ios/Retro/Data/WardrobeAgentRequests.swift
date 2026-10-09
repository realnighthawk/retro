import CryptoKit
import Foundation
import Observation

struct WardrobeAgentRequest: Codable, Identifiable {
    let id: String
    let query: String
    let createdAt: Date
    var dispatched = false
    var cancellationRequested = false
    var response: GatewayAgentResponse?
    var latest: GatewayAgentResult?
    var problem: String?
    var terminal: Bool { latest?.status.terminal == true }
    var pendingInput: GatewayAgentInput? { cancellationRequested || response != nil || terminal ? nil : latest?.pending_input }
    var call: GatewayAgentCall { GatewayAgentCall(request_id: id, query: query, cancel: cancellationRequested, response: cancellationRequested ? nil : response) }
    var statusText: String {
        if terminal { return latest?.status == .completed ? "Completed" : latest?.status == .cancelled ? "Stopped" : "Failed" }
        if cancellationRequested { return "Stop pending" }
        if response != nil { return "Sending your answer" }
        if pendingInput != nil { return "Needs your answer" }
        return dispatched ? "Working or awaiting confirmation" : "Ready to send"
    }
}

@MainActor @Observable final class WardrobeAgentRequests {
    private(set) var items: [WardrobeAgentRequest] = []
    private(set) var storageProblem: String?
    private(set) var sending = false
    let owner: String
    private let stillOwner: () -> Bool
    private let save: ([WardrobeAgentRequest]) throws -> Void
    private let send: (GatewayAgentCall) async throws -> GatewayAgentResult
    var isCurrentOwner: Bool { stillOwner() }

    convenience init(engine: Engine) {
        let client = GatewayMCP(engine: engine)
        let scope = SHA256.hash(data: Data(engine.gatewayScope.utf8)).map { String(format: "%02x", $0) }.joined()
        self.init(file: DiskCache(owner: engine.owner).durableURL("agent-requests-\(scope)"), owner: engine.owner,
                  stillOwner: { engine.isCurrentOwner }) { try await client.ask($0) }
    }

    init(file: URL, owner: String, stillOwner: @escaping () -> Bool,
         save: (([WardrobeAgentRequest]) throws -> Void)? = nil,
         send: @escaping (GatewayAgentCall) async throws -> GatewayAgentResult) {
        self.owner = owner; self.stillOwner = stillOwner; self.send = send
        self.save = save ?? { items in
            let bytes = try JSONEncoder().encode(items)
            guard bytes.count <= 512 * 1024 else { throw WardrobeWriteError("Saved connected requests exceed their limit.") }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            var folder = file.deletingLastPathComponent(); var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
            try folder.setResourceValues(attributes)
            try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 512 * 1024 else { throw WardrobeWriteError("Saved requests are too large.") }
                let data = try Data(contentsOf: file)
                guard data.count <= 512 * 1024 else { throw WardrobeWriteError("Saved requests are too large.") }
                let restored = try JSONDecoder().decode([WardrobeAgentRequest].self, from: data)
                guard restored.count <= 12, Set(restored.map(\.id)).count == restored.count else { throw WardrobeWriteError("Invalid saved request list.") }
                for item in restored {
                    try Self.validateQuery(item.query)
                    guard let id = UUID(uuidString: item.id), id.uuidString.lowercased() == item.id,
                          item.id != "00000000-0000-0000-0000-000000000000" else { throw WardrobeWriteError("Invalid saved request identity.") }
                    if let latest = item.latest {
                        guard let date = GatewayAgentResult.date(latest.retrieved_at) else { throw WardrobeWriteError("Invalid saved snapshot.") }
                        try latest.validate(requestID: item.id, owner: owner, now: date)
                    }
                    if let response = item.response {
                        guard !item.cancellationRequested, let input = item.latest?.pending_input else { throw WardrobeWriteError("Invalid saved owner response.") }
                        try response.validate(input)
                    }
                }
                items = restored
            }
        } catch { storageProblem = "Saved connected requests could not be opened. They were kept in place; new requests are blocked." }
    }

    nonisolated static func validateQuery(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 4000 else { throw WardrobeWriteError("Keep the connected query within 4000 UTF-8 bytes.") }
    }

    func begin(_ query: String) throws -> String {
        try guardOwner(); try Self.validateQuery(query)
        guard items.filter({ !$0.terminal }).count < 8 else { throw WardrobeWriteError("Check or stop existing connected requests before starting another.") }
        let item = WardrobeAgentRequest(id: UUID().uuidString.lowercased(), query: query, createdAt: Date())
        let keep = Array(items.filter(\.terminal).suffix(3)) + items.filter { !$0.terminal }
        try commit(keep + [item])
        return item.id
    }

    func item(_ id: String) -> WardrobeAgentRequest? { items.first { $0.id == id } }

    func answer(_ id: String, response: GatewayAgentResponse) throws {
        try guardOwner()
        guard var item = item(id), let input = item.pendingInput else { throw WardrobeWriteError("This question changed or already has an answer.") }
        try response.validate(input)
        item.response = response; item.problem = nil
        try replace(item)
    }

    // A stop intent is stored even during logout; only this owner's token can send it later.
    func requestCancellation(_ ids: Set<String>) throws {
        guard items.contains(where: { ids.contains($0.id) && !$0.terminal }) else { return }
        guard storageProblem == nil else { throw WardrobeWriteError(storageProblem!) }
        var next = items
        for i in next.indices where ids.contains(next[i].id) && !next[i].terminal {
            next[i].cancellationRequested = true; next[i].response = nil; next[i].problem = nil
        }
        try commit(next)
    }

    func perform(_ id: String) async throws -> GatewayAgentResult {
        try guardOwner(); try Task.checkCancellation()
        guard !sending, var item = item(id) else { throw WardrobeWriteError("Another connected request is being checked. Try again shortly.") }
        sending = true; defer { sending = false }
        item.dispatched = true; item.problem = nil
        try replace(item)
        do {
            let result = try await send(item.call)
            try Task.checkCancellation(); try guardOwner()
            try result.validate(requestID: id, owner: owner)
            guard var current = self.item(id) else { throw WardrobeWriteError("The saved request changed.") }
            if current.cancellationRequested && !result.status.terminal && !item.cancellationRequested {
                throw CancellationError()
            }
            current.latest = result; current.problem = nil
            if result.status.terminal || result.pending_input?.request_id != current.response?.request_id { current.response = nil }
            try replace(current)
            return result
        } catch {
            if stillOwner(), !Task.isCancelled, var current = self.item(id) {
                current.problem = error.localizedDescription
                try? replace(current)
            }
            throw error
        }
    }

    func retryCancellations() async {
        guard stillOwner(), storageProblem == nil, !sending else { return }
        for id in items.filter({ $0.cancellationRequested && !$0.terminal }).map(\.id) {
            guard stillOwner(), !Task.isCancelled, !sending else { return }
            _ = try? await perform(id)
        }
    }

    private func guardOwner() throws {
        guard stillOwner() else { throw WardrobeWriteError("Sign in to the original account to check this request.") }
        guard storageProblem == nil else { throw WardrobeWriteError(storageProblem!) }
    }
    private func replace(_ item: WardrobeAgentRequest) throws {
        var next = items
        guard let i = next.firstIndex(where: { $0.id == item.id }), next[i].query == item.query else { throw WardrobeWriteError("The original connected request changed.") }
        next[i] = item; try commit(next)
    }
    private func commit(_ next: [WardrobeAgentRequest]) throws { try save(next); items = next }
}
