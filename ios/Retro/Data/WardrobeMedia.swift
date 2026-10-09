import Foundation

struct WardrobeMedia: Codable {
    let id: String
    let version: Int64
    let checksum: String
    let sizeBytes: Int64
    let mimeType: String
    let state: String
    let width: Int?
    let height: Int?
    let error: String?
    let uploadPath: String
    let displayPath: String?
    let thumbnailPath: String?
    enum CodingKeys: String, CodingKey {
        case id, version, checksum, state, width, height, error
        case sizeBytes = "size_bytes", mimeType = "mime_type", uploadPath = "upload_path"
        case displayPath = "display_path", thumbnailPath = "thumbnail_path"
    }
}
struct WardrobeMediaResult: Codable { let media: WardrobeMedia }

enum WardrobeMediaPath {
    // Construct only contract paths under the configured API origin; never follow a server-supplied URL.
    static func path(id: String, variant: String? = nil) -> String? {
        guard let uuid = UUID(uuidString: id), uuid.uuidString.lowercased() == id.lowercased(), id != "00000000-0000-0000-0000-000000000000",
              variant == nil || ["display", "thumbnail"].contains(variant!) else { return nil }
        return "/media/\(id.lowercased())/content" + (variant.map { "?variant=\($0)" } ?? "")
    }
}

final class WardrobeBinarySession: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: WardrobeBinarySession(), delegateQueue: nil)
    }()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

extension Api {
    var pausesPhotoDelivery: Bool {
        switch self { case .unauthorized, .notProvisioned, .retry, .serverError: true; default: false }
    }
}
