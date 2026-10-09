import Foundation
import Security

struct OnboardingProgress: Decodable {
    let status: String
    let error: String?
}

struct OnboardingAccepted: Decodable { let status: String }

struct OnboardingRequest: Encodable {
    let llmTiers: [String: String] = [:]
    let postgresPassword: String
    let agentBrainDbPassword: String
    let agentBrainApiKey: String
    let agentBrainJwtSecret: String
    let mcpHubDbPassword: String

    enum CodingKeys: String, CodingKey {
        case llmTiers = "llm_tiers", postgresPassword = "postgres_password"
        case agentBrainDbPassword = "agent_brain_db_password", agentBrainApiKey = "agent_brain_api_key"
        case agentBrainJwtSecret = "agent_brain_jwt_secret", mcpHubDbPassword = "mcp_hub_db_password"
    }

    static func make() throws -> Self {
        func secret() throws -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecNotAvailable))
            }
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return try Self(postgresPassword: secret(), agentBrainDbPassword: secret(), agentBrainApiKey: secret(),
                        agentBrainJwtSecret: secret(), mcpHubDbPassword: secret())
    }
}

@MainActor @Observable
final class OnboardingModel {
    enum Phase: Hashable { case checking, setup, provisioning, ready, failed, unavailable }
    private(set) var phase: Phase = .checking
    private(set) var working = false
    private(set) var problem: String?
    private let status: () async -> Api<OnboardingProgress>
    private let submit: (OnboardingRequest) async -> Api<OnboardingAccepted>

    init(status: @escaping () async -> Api<OnboardingProgress>, submit: @escaping (OnboardingRequest) async -> Api<OnboardingAccepted>) {
        self.status = status
        self.submit = submit
    }

    func refresh() async {
        guard !working else { return }
        working = true
        defer { working = false }
        _ = await readStatus()
    }

    func start() async {
        guard !working, phase == .setup || phase == .failed else { return }
        working = true
        defer { working = false }
        // The server is authoritative across relaunches and other clients; never replay completed or running setup.
        guard await readStatus(), phase == .setup || phase == .failed, !Task.isCancelled else { return }
        guard let request = try? OnboardingRequest.make() else { problem = "Couldn't securely prepare setup. Try again."; return }
        switch await submit(request) {
        case .ok:
            phase = .provisioning
            problem = nil
        default:
            // The response may have been lost after acceptance. Recheck before any later retry.
            problem = "Couldn't confirm setup. Check your connection and try again."
        }
    }

    func watch() async {
        while phase == .provisioning && !Task.isCancelled {
            await refresh()
            guard phase == .provisioning else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
        }
    }

    private func readStatus() async -> Bool {
        let result = await status()
        guard !Task.isCancelled else { return false }
        switch result {
        case .ok(let progress):
            problem = nil
            switch progress.status {
            case "completed": phase = .ready
            case "pending", "running", "awaiting_approval": phase = .provisioning
            case "failed": phase = .failed; problem = "Setup didn't finish. You can try again."
            default: phase = .unavailable; problem = "Couldn't read setup progress."; return false
            }
            return true
        case .failed(_, let message) where message == "no onboarding request found":
            phase = .setup
            problem = nil
            return true
        default:
            problem = result.problem
            // Like the other clients, an offline check must not lock an existing account out of the app.
            if phase == .checking { phase = .ready }
            return false
        }
    }
}
