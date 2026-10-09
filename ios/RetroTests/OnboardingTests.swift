import XCTest
@testable import Retro

@MainActor
final class OnboardingTests: XCTestCase {
    func testOfflineInitialCheckDoesNotLockTheAccountOut() async {
        let results: [Api<OnboardingProgress>] = [.retry("offline"), .unauthorized]
        for result in results {
            let model = OnboardingModel(status: { result }, submit: { _ in
                XCTFail("an inconclusive check must never provision"); return .ok(.init(status: "accepted"))
            })
            await model.refresh()
            await model.start()
            XCTAssertEqual(model.phase, .ready)
        }
    }

    func testCompletedOrRunningSetupNeverSubmits() async {
        for status in ["completed", "running", "pending", "awaiting_approval"] {
            var submitted = 0
            let model = OnboardingModel(status: { .ok(.init(status: status, error: nil)) }, submit: { _ in
                submitted += 1; return .ok(.init(status: "accepted"))
            })
            await model.refresh()
            await model.start()
            XCTAssertEqual(submitted, 0)
            XCTAssertEqual(model.phase, status == "completed" ? .ready : .provisioning)
        }
    }

    func testLostSubmissionResponseResumesWithoutReposting() async {
        var accepted = false
        var submitted = 0
        let model = OnboardingModel(status: {
            accepted ? .ok(.init(status: "running", error: nil)) : .failed(code: nil, message: "no onboarding request found")
        }, submit: { _ in
            submitted += 1; accepted = true; return .retry("offline")
        })
        await model.refresh()
        await model.start()
        await model.start()
        XCTAssertEqual(submitted, 1)
        XCTAssertEqual(model.phase, .provisioning)

        let relaunched = OnboardingModel(status: { .ok(.init(status: "running", error: nil)) }, submit: { _ in
            XCTFail("a relaunched app must only watch existing setup"); return .ok(.init(status: "accepted"))
        })
        await relaunched.refresh()
        XCTAssertEqual(relaunched.phase, .provisioning)
    }

    func testTransientOrUnrecognizedStatusNeverStartsSetup() async {
        var result: Api<OnboardingProgress> = .failed(code: nil, message: "no onboarding request found")
        var submitted = 0
        let model = OnboardingModel(status: { result }, submit: { _ in
            submitted += 1; return .ok(.init(status: "accepted"))
        })
        await model.refresh()
        result = .retry("offline")
        await model.start()
        XCTAssertEqual(submitted, 0)
        result = .ok(.init(status: "unexpected", error: nil))
        await model.start()
        XCTAssertEqual(submitted, 0)
        XCTAssertEqual(model.phase, .unavailable)
    }

    func testDoubleTapSubmitsOnceAndFailedSetupCanRetry() async {
        var submitted = 0
        let model = OnboardingModel(status: { .ok(.init(status: "failed", error: nil)) }, submit: { _ in
            submitted += 1
            await Task.yield(); return .ok(.init(status: "accepted"))
        })
        await model.refresh()
        async let first: Void = model.start()
        async let second: Void = model.start()
        _ = await (first, second)
        XCTAssertEqual(submitted, 1)
        XCTAssertEqual(model.phase, .provisioning)
    }

    func testRequestUsesPlatformDefaultsAndIndependentSecureSecrets() throws {
        let data = try JSONEncoder().encode(OnboardingRequest.make())
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((body["llm_tiers"] as? [String: String])?.count, 0)
        let keys = ["postgres_password", "agent_brain_db_password", "agent_brain_api_key", "agent_brain_jwt_secret", "mcp_hub_db_password"]
        let secrets = try keys.map { try XCTUnwrap(body[$0] as? String) }
        XCTAssertEqual(Set(secrets).count, 5)
        XCTAssertTrue(secrets.allSatisfy { $0.count == 64 && $0.allSatisfy(\.isHexDigit) })
    }

    func testAnotherAccountCannotCheckOrSubmitOnboarding() async throws {
        var fetched = 0
        let engine = Engine(owner: "A", currentUser: { "B" }, token: { _ in fetched += 1; return "B-token" })
        guard case .unauthorized = await engine.onboardingStatus() else { return XCTFail("wrong account") }
        guard case .unauthorized = await engine.startOnboarding(try OnboardingRequest.make()) else { return XCTFail("wrong account") }
        XCTAssertEqual(fetched, 0)
    }

    func testExpiredHistoryCannotProvisionAnExistingWorkspace() async {
        var paths: [String] = []
        OnboardingHTTP.response = { request in
            paths.append(request.url!.path)
            if request.url!.path == "/onboard" { return (404, Data(#"{"error":"no onboarding request found"}"#.utf8)) }
            return (200, Data())
        }
        defer { OnboardingHTTP.response = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OnboardingHTTP.self]
        let router = RetroAPI(baseURL: "https://router.test", session: URLSession(configuration: configuration))
        let engine = Engine(owner: "A", router: router, currentUser: { "A" }, token: { _ in "A-token" })
        let model = OnboardingModel(status: { await engine.onboardingStatus() }, submit: { await engine.startOnboarding($0) })
        await model.refresh()
        await model.start()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(paths, ["/onboard", "/gateway/healthz"])
    }
}

private final class OnboardingHTTP: URLProtocol {
    static var response: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, data) = Self.response!(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
