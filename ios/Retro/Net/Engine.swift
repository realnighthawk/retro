import Foundation

/// The engine for ONE user: fetches the Clerk token, and retries once with a fresh one on 401.
///
/// It is bound to the user it was created for. The auth state is shared, so a request still running for user A after
/// the phone switched to user B would otherwise pick up B's token and write A's data into B's account. Every call
/// checks that the signed-in user is still `owner`, and fails as unauthorized — sending nothing — when it isn't.
@MainActor
final class Engine {
    let owner: String
    var isCurrentOwner: Bool { currentUser() == owner }
    var cacheScope: String { api.baseURL }

    private let api: RetroAPI
    private let router: RetroAPI
    private let currentUser: () -> String?
    private let token: (Bool) async -> String?

    init(
        owner: String,
        api: RetroAPI = .live,
        router: RetroAPI = RetroAPI(baseURL: Config.routerBaseURL),
        currentUser: @escaping () -> String?,
        token: @escaping (Bool) async -> String?
    ) {
        self.owner = owner
        self.api = api
        self.router = router
        self.currentUser = currentUser
        self.token = token
    }

    func call<In: Encodable, Out: Decodable>(_ op: String, _ input: In) async -> Api<Out> {
        await authenticated { await self.api.call(op, input, token: $0) }
    }

    func callFrozen<Out: Decodable>(_ op: String, body: Data) async -> Api<Out> {
        await authenticated { await self.api.request("POST", "/operations/\(op)", body: body, token: $0) }
    }

    func uploadPhoto(_ id: String, bytes: Data) async -> Api<WardrobeMediaResult> {
        guard let path = WardrobeMediaPath.path(id: id) else { return .failed(code: "invalid_input", message: "Invalid photo identity.") }
        return await authenticated { await self.api.request("PUT", path, body: bytes, token: $0, contentType: "image/jpeg", transport: self.api.binarySession) }
    }

    func photo(_ id: String, variant: String) async -> Api<Data> {
        guard let path = WardrobeMediaPath.path(id: id, variant: variant) else { return .failed(code: "invalid_input", message: "Invalid photo identity.") }
        return await authenticated { await self.api.request("GET", path, token: $0, transport: self.api.binarySession, decode: {
            guard !$0.isEmpty, $0.count <= 12 * 1024 * 1024 else { throw WardrobeWriteError("Photo is too large.") }
            return $0
        }) }
    }

    func onboardingStatus() async -> Api<OnboardingProgress> {
        let status: Api<OnboardingProgress> = await authenticated { await self.router.request("GET", "/onboard", token: $0) }
        if case .failed(_, "no onboarding request found") = status {
            // Temporal history can expire; an existing workspace must never be provisioned again because of that.
            let health: Api<Bool> = await authenticated {
                await self.router.request("GET", "/gateway/healthz", token: $0, decode: { _ in true })
            }
            switch health {
            case .ok: return .ok(.init(status: "completed", error: nil))
            case .notProvisioned: return status
            default: return health.failure()!
            }
        }
        return status
    }

    func startOnboarding(_ input: OnboardingRequest) async -> Api<OnboardingAccepted> {
        guard let body = try? JSONEncoder().encode(input) else { return .failed(code: nil, message: "Bad request") }
        return await authenticated { await self.router.request("POST", "/onboard", body: body, token: $0) }
    }

    private func authenticated<Out>(_ send: (String) async -> Api<Out>) async -> Api<Out> {
        guard currentUser() == owner else { return .unauthorized }
        guard let sessionToken = await token(false), currentUser() == owner else { return .unauthorized }

        let result = await send(sessionToken)
        guard currentUser() == owner else { return .unauthorized }
        if case .unauthorized = result,
           currentUser() == owner,
           let fresh = await token(true),
           currentUser() == owner {
            let refreshed = await send(fresh)
            return currentUser() == owner ? refreshed : .unauthorized
        }
        return result
    }
}
