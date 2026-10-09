import Foundation

/// The outcome of one engine call. These are the cases the UI branches on, so nothing downstream ever inspects a status
/// code or a raw error body.
enum Api<T> {
    case ok(T)
    case unauthorized
    /// The router has no instance for this user yet.
    case notProvisioned
    /// Couldn't reach the engine, or it is busy or restarting (offline, 408, 429, 502-504). The same request is safe to resend.
    case retry(String)
    /// The engine answered 500: probably transient, possibly a bug that will repeat. Resend a few times, then give up.
    case serverError(String)
    /// The engine understood and said no; `code` is its machine-readable reason.
    case failed(code: String?, message: String)
}

extension Api {
    /// A short, human line for a failed call; nil when it succeeded.
    var problem: String? {
        switch self {
        case .ok: nil
        case .unauthorized: "Session expired. Sign in again."
        case .notProvisioned: "Your Retro service isn't set up yet."
        case .retry(let message): "Couldn't reach Retro: \(message)"
        case .serverError(let message): "Retro had a problem (\(message)). Try again in a moment."
        case .failed(_, let message): message
        }
    }

    func map<U>(_ transform: (T) -> U) -> Api<U> {
        switch self {
        case .ok(let value): .ok(transform(value))
        case .unauthorized: .unauthorized
        case .notProvisioned: .notProvisioned
        case .retry(let message): .retry(message)
        case .serverError(let message): .serverError(message)
        case .failed(let code, let message): .failed(code: code, message: message)
        }
    }

    /// This result re-typed, when it isn't a success; nil for a success.
    func failure<U>() -> Api<U>? {
        switch self {
        case .ok: nil
        case .unauthorized: .unauthorized
        case .notProvisioned: .notProvisioned
        case .retry(let message): .retry(message)
        case .serverError(let message): .serverError(message)
        case .failed(let code, let message): .failed(code: code, message: message)
        }
    }
}

/// Every operation is `POST <router>/retro/api/v1/operations/<name>` with a JSON object body, like the rest of the
/// family. Models declare explicit `CodingKeys` with snake_case raw values rather than leaning on a decoder strategy.
struct RetroAPI {
    let baseURL: String
    var session: URLSession = .shared
    var binarySession: URLSession = WardrobeBinarySession.shared

    static var live: RetroAPI {
        RetroAPI(baseURL: (Config.devEngineURL ?? (Config.routerBaseURL + Config.servicePath)) + "/api/v1")
    }

    func call<In: Encodable, Out: Decodable>(_ op: String, _ input: In, token: String, timeout: TimeInterval = 30) async -> Api<Out> {
        guard let body = try? JSONEncoder().encode(input) else { return .failed(code: nil, message: "Bad request") }
        return await request("POST", "/operations/\(op)", body: body, token: token, timeout: timeout)
    }

    func request<Out: Decodable>(_ method: String, _ path: String, body: Data? = nil, token: String, timeout: TimeInterval = 30,
                                 contentType: String = "application/json", transport: URLSession? = nil,
                                 decode: (Data) throws -> Out = { try JSONDecoder().decode(Out.self, from: $0) }) async -> Api<Out> {
        var root = baseURL
        while root.hasSuffix("/") { root.removeLast() }
        guard let endpoint = URL(string: root + path) else {
            return .failed(code: nil, message: "Bad request")
        }

        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await (transport ?? session).data(for: request),
              let http = response as? HTTPURLResponse else {
            return .retry("network error")
        }
        return RetroAPI.classify(http.statusCode, data, decode: decode)
    }

    static func classify<T: Decodable>(_ code: Int, _ data: Data,
                                       decode: (Data) throws -> T = { try JSONDecoder().decode(T.self, from: $0) }) -> Api<T> {
        switch code {
        case 200...299:
            do {
                return .ok(try decode(data))
            } catch {
                return .retry("unreadable response")
            }
        case 401, 403:
            return .unauthorized
        case 404 where String(decoding: data, as: UTF8.self).contains("no_tenant"):
            return .notProvisioned
        case 408, 429, 502...504:
            return .retry("server returned \(code)")
        case 500...:
            return .serverError("server returned \(code)")
        default:
            let (errorCode, message) = errorOf(data)
            return .failed(code: errorCode, message: message ?? "The server returned \(code).")
        }
    }

    /// Engine errors are `{"error":{"code","message"}}`; the router's are `{"error":"..."}`.
    static func errorOf(_ data: Data) -> (code: String?, message: String?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] else { return (nil, nil) }
        if let nested = error as? [String: Any] {
            return (nested["code"] as? String, nested["message"] as? String)
        }
        if let text = error as? String { return (nil, text) }
        return (nil, nil)
    }
}
