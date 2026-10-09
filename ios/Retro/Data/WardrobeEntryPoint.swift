import Foundation
import Observation

enum WardrobeEntryAction: Equatable {
    case add, search(String), today
    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == "org.nighthawklabs.retro", parts.host == "wardrobe", parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil else { return nil }
        let queries = parts.queryItems ?? []
        switch parts.path {
        case "/add" where queries.isEmpty: self = .add
        case "/today" where queries.isEmpty: self = .today
        case "/search" where queries.count == 1 && queries[0].name == "q":
            guard let text = queries[0].value, text.utf8.count <= 100, !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            self = .search(text)
        default: return nil
        }
    }
    var url: URL {
        var parts = URLComponents(); parts.scheme = "org.nighthawklabs.retro"; parts.host = "wardrobe"
        switch self {
        case .add: parts.path = "/add"
        case .today: parts.path = "/today"
        case .search(let text): parts.path = "/search"; parts.queryItems = [URLQueryItem(name: "q", value: text)]
        }
        return parts.url!
    }
}
struct WardrobeEntryRequest: Identifiable {
    let id = UUID()
    let action: WardrobeEntryAction
}
@MainActor @Observable final class WardrobeEntryPoint {
    static let shared = WardrobeEntryPoint()
    var pending: WardrobeEntryRequest?
    func open(_ url: URL) { if let action = WardrobeEntryAction(url: url) { pending = WardrobeEntryRequest(action: action) } }
    func consume(owner: Bool) -> WardrobeEntryAction? {
        guard owner else { return nil }
        let action = pending?.action; pending = nil; return action
    }
}
