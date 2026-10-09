import Foundation

// Int64 is decoded before floating-point numbers so record versions never pass through Double.
indirect enum GatewayJSON: Codable, Equatable {
    case object([String: GatewayJSON]), array([GatewayJSON]), string(String), integer(Int64), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        guard decoder.codingPath.count < 32 else { throw WardrobeWriteError("Connected data is too deeply nested.") }
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .integer(v) }
        else if let v = try? c.decode(Double.self), v.isFinite { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: GatewayJSON].self) { self = .object(v) }
        else { self = .array(try c.decode([GatewayJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> GatewayJSON? { if case .object(let v) = self { return v[key] }; return nil }
    var text: String? { if case .string(let v) = self { return v }; return nil }
    var values: [GatewayJSON]? { if case .array(let v) = self { return v }; return nil }
    var flag: Bool? { if case .bool(let v) = self { return v }; return nil }
    var fields: [String: GatewayJSON]? { if case .object(let v) = self { return v }; return nil }
}

enum GatewayAgentStatus: String, Codable {
    case running, needsInput = "needs_input", cancelling, completed, failed, cancelled
    var terminal: Bool { [.completed, .failed, .cancelled].contains(self) }
}
struct GatewayAgentOption: Codable, Equatable, Identifiable { let id: String; let label: String }
struct GatewayAgentInput: Codable, Equatable {
    let request_id: String
    let kind: String
    let prompt: String
    let options: [GatewayAgentOption]
    let allow_free_text: Bool
}
struct GatewayAgentResponse: Codable, Equatable {
    let request_id: String
    var selected_option_id: String?
    var free_text: String?
    func validate(_ input: GatewayAgentInput) throws {
        guard request_id == input.request_id, (selected_option_id == nil) != (free_text == nil) else {
            throw WardrobeWriteError("The input changed. Review the latest request.")
        }
        if let option = selected_option_id {
            guard input.options.contains(where: { $0.id == option }) else { throw WardrobeWriteError("Choose an offered option.") }
        }
        if let text = free_text {
            guard input.allow_free_text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 4000 else {
                throw WardrobeWriteError("A short written answer is not permitted for this request.")
            }
        }
    }
}
struct GatewayAgentSource: Codable {
    let tool_call_id: String
    let tool_name: String
    let status: String
    let result: GatewayJSON?
    let truncated: Bool?
    let started_at: String
    let completed_at: String?
    var server: String? = nil
    var tool: String? = nil
}
struct GatewayAgentResult: Codable {
    static let maxSourceBytes = 4096
    static let maxResultBytes = 32 * 1024
    let schema_version: Int
    let request_id: String
    let session_id: String
    let turn_id: String
    let status: GatewayAgentStatus
    let retrieved_at: String
    let completed_at: String?
    let answer: String?
    let truncated: Bool
    let coverage: String
    let sources: [GatewayAgentSource]?
    let pending_input: GatewayAgentInput?
    let retry_after_ms: Int?

    func validate(requestID: String, owner: String, now: Date = Date()) throws {
        let sourceList = sources ?? []
        guard schema_version == 1, request_id == requestID,
              session_id.hasPrefix("mcp-"), session_id.hasSuffix("-" + requestID), session_id.utf8.count <= 128,
              turn_id == "agent:main:web:user:\(owner):session:\(session_id):turn:1",
              coverage == "recent_top_level_tool_calls", (answer?.utf8.count ?? 0) <= 6000,
              let retrieved = Self.date(retrieved_at), abs(retrieved.timeIntervalSince(now)) <= 300,
              sourceList.count <= 6, Set(sourceList.map(\.tool_call_id)).count == sourceList.count,
              (status == .needsInput) == (pending_input != nil),
              retry_after_ms == nil || (100...10_000).contains(retry_after_ms!),
              (try JSONEncoder().encode(self)).count <= Self.maxResultBytes else { throw WardrobeWriteError("Connected help returned an unsupported or mismatched result.") }
        if let completed_at { guard let closed = Self.date(completed_at), closed <= retrieved.addingTimeInterval(300) else { throw WardrobeWriteError("Connected completion time is invalid.") } }
        for source in sourceList {
            guard source.tool_call_id.hasPrefix(turn_id + ":"), !source.tool_name.isEmpty, source.tool_name.utf8.count <= 256,
                  ["pending", "ok", "error", "cancelled"].contains(source.status),
                  let started = Self.date(source.started_at), started <= retrieved.addingTimeInterval(300),
                  source.truncated != true || truncated else { throw WardrobeWriteError("Connected evidence is invalid.") }
            if let value = source.result, try JSONEncoder().encode(value).count > Self.maxSourceBytes { throw WardrobeWriteError("Connected evidence exceeds its limit.") }
            guard (source.server == nil) == (source.tool == nil), source.server == nil || (source.tool_name == "call_tool" && source.server!.utf8.count > 0 && source.server!.utf8.count <= 128 && source.tool!.utf8.count > 0 && source.tool!.utf8.count <= 256) else { throw WardrobeWriteError("Connected source identity is invalid.") }
            if let closed = source.completed_at { guard let date = Self.date(closed), date >= started, date <= retrieved.addingTimeInterval(300) else { throw WardrobeWriteError("Connected evidence time is invalid.") } }
        }
        if let p = pending_input {
            guard p.request_id.hasPrefix(turn_id + ":"), p.request_id.utf8.count <= 1024,
                  !p.prompt.isEmpty, p.prompt.utf8.count <= 4000, !p.kind.isEmpty, p.kind.utf8.count <= 128,
                  p.options.count <= 32, Set(p.options.map(\.id)).count == p.options.count,
                  p.options.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 256 && !$0.label.isEmpty && $0.label.utf8.count <= 1000 }) else {
                throw WardrobeWriteError("This permission or question cannot be safely previewed. Review it in the gateway.")
            }
        }
    }
    static func date(_ text: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: text) { return date }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: text)
    }
}

struct GatewayAgentCall: Encodable {
    let request_id: String
    let query: String
    var cancel = false
    var response: GatewayAgentResponse?
}

struct GatewayAgentError: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { message }
}

@MainActor final class GatewayMCP {
    private let engine: Engine
    private let session: URLSession
    private var negotiated: String?
    init(engine: Engine, session: URLSession = WardrobeBinarySession.shared) { self.engine = engine; self.session = session }

    // shortcut: the gateway's stateless JSON profile only; use the Swift MCP transport when the gateway adds SSE or transport sessions.
    func ask(_ call: GatewayAgentCall) async throws -> GatewayAgentResult {
        guard engine.isCurrentOwner, Config.devEngineURL == nil else { throw WardrobeWriteError("Connected help needs your signed-in gateway.") }
        if negotiated == nil { try await initialize() }
        let arguments = try JSONDecoder().decode(GatewayJSON.self, from: JSONEncoder().encode(call))
        let result = try await rpc("tools/call", .object(["name": .string("ask_agent"), "arguments": arguments]))
        let body: Data
        if let structured = result["structuredContent"] {
            body = try JSONEncoder().encode(structured)
        } else {
            guard let content = result["content"]?.values, content.count == 1,
                  content[0]["type"]?.text == "text", let text = content[0]["text"]?.text, text.utf8.count <= GatewayAgentResult.maxResultBytes else {
                throw WardrobeWriteError("Connected help returned an unsupported tool response.")
            }
            body = Data(text.utf8)
            if let value = try? JSONDecoder().decode(GatewayJSON.self, from: body), let code = value["error"]?["code"]?.text {
                let messages = ["not_found": "This request is not visible yet. Keep its saved identity and check again.",
                                "request_conflict": "The saved request does not match this execution. It will not be restarted.",
                                "execution_unavailable": "The recorded execution is unavailable. It will not be restarted.",
                                "result_too_large": "This request is too large to review here. Review it in the gateway or stop it."]
                throw GatewayAgentError(code: code, message: messages[code] ?? "Connected help is unavailable. Check the saved request again.")
            }
        }
        guard body.count <= GatewayAgentResult.maxResultBytes else { throw WardrobeWriteError("Connected help exceeded its response limit.") }
        let value = try JSONDecoder().decode(GatewayAgentResult.self, from: body)
        try value.validate(requestID: call.request_id, owner: engine.owner)
        guard result["isError"]?.flag != true || [.failed, .cancelled].contains(value.status) else { throw WardrobeWriteError("Connected help reported a failed response.") }
        return value
    }

    private func initialize() async throws {
        let result = try await rpc("initialize", .object([
            "protocolVersion": .string("2025-06-18"), "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("Retro iOS"), "version": .string("1.0.0")])
        ]))
        guard let version = result["protocolVersion"]?.text, ["2025-06-18", "2025-03-26"].contains(version),
              result["serverInfo"]?["name"]?.text == "agent-harness-gateway", result["capabilities"]?["tools"]?.fields != nil else {
            throw WardrobeWriteError("This service does not offer compatible connected help yet.")
        }
        try await notify("notifications/initialized", version: version)
        let listing = try await rpc("tools/list", .object([:]), version: version)
        guard let tools = listing["tools"]?.values,
              tools.filter({ $0["name"]?.text == "ask_agent" }).count == 1,
              let tool = tools.first(where: { $0["name"]?.text == "ask_agent" }),
              tool["inputSchema"]?["properties"]?["query"]?["type"]?.text == "string",
              tool["inputSchema"]?["properties"]?["request_id"]?["type"]?.text == "string",
              tool["outputSchema"]?["type"]?.text == "object" else { throw WardrobeWriteError("The connected query tool is unavailable or has changed.") }
        try Task.checkCancellation()
        guard engine.isCurrentOwner else { throw WardrobeWriteError("Sign in again before using connected help.") }
        negotiated = version
    }

    private func rpc(_ method: String, _ params: GatewayJSON, version: String? = nil) async throws -> GatewayJSON {
        let id = UUID().uuidString.lowercased()
        let body = try JSONEncoder().encode(GatewayJSON.object(["jsonrpc": .string("2.0"), "id": .string(id), "method": .string(method), "params": params]))
        let data = try await post(body, version: version ?? negotiated ?? "2025-06-18", notification: false)
        let envelope = try JSONDecoder().decode(GatewayJSON.self, from: data)
        guard envelope["jsonrpc"]?.text == "2.0", envelope["id"]?.text == id, envelope["error"] == nil,
              let result = envelope["result"], result.fields != nil else { throw WardrobeWriteError("Connected help returned an invalid MCP response.") }
        return result
    }
    private func notify(_ method: String, version: String) async throws {
        let body = try JSONEncoder().encode(GatewayJSON.object(["jsonrpc": .string("2.0"), "method": .string(method)]))
        _ = try await post(body, version: version, notification: true)
    }

    private func post(_ body: Data, version: String, notification: Bool) async throws -> Data {
        guard body.count <= 32 * 1024, let url = URL(string: engine.gatewayScope), url.scheme == "https",
              url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw WardrobeWriteError("The connected help address is invalid.") }
        let outcome: Api<Data> = await engine.authenticated { token in
            do {
                try Task.checkCancellation()
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
                request.httpMethod = "POST"; request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
                request.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (bytes, response) = try await self.session.bytes(for: request)
                defer { bytes.task.cancel() }
                guard let http = response as? HTTPURLResponse else { return .retry("missing response") }
                if (200...299).contains(http.statusCode) {
                    let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased().components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces)
                    guard http.value(forHTTPHeaderField: "Mcp-Session-Id") == nil,
                          (notification ? http.statusCode == 202 : contentType == "application/json") else {
                        return .failed(code: "unsupported_transport", message: "Connected help requires an updated transport.")
                    }
                }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < 128 * 1024 else { return .failed(code: "too_large", message: "Connected help exceeded its wire limit.") }
                    data.append(byte)
                }
                if notification, (200...299).contains(http.statusCode), !data.isEmpty {
                    return .failed(code: "unsupported_transport", message: "Connected help returned an invalid notification acknowledgment.")
                }
                return RetroAPI.classify(http.statusCode, data, decode: { $0 })
            } catch { return .retry("network error") }
        }
        try Task.checkCancellation()
        guard case .ok(let data) = outcome else { throw WardrobeWriteError(outcome.problem ?? "Connected help is unavailable.") }
        return data
    }
}
