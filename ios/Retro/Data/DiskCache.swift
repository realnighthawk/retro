import CryptoKit
import Foundation

/// This user's files on this phone, in two tiers because iOS treats the two directories differently.
///
/// - `durable: true` → Application Support. The OS never purges it, so a day the owner recorded but that has not
///   reached the engine yet goes here. A year of days is the point of the product; losing one to storage pressure
///   would lose the thing itself.
/// - `durable: false` → Caches. Re-fetchable reads, dropped on sign-out and under storage pressure.
///
/// ponytail: one JSON file per key, written whole. Move to SwiftData when a list has to be queried or edited offline
/// rather than replaced wholesale — the day record is the first that will need it.
struct DiskCache {
    let owner: String

    private var folder: String {
        // A plain ASCII id keeps the folder readable. Anything else is hashed, because a mangled id could collide
        // with another user's folder, and a guess is exactly how one account's days reach another.
        let safe = !owner.isEmpty && owner.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        guard safe else {
            return SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        return owner
    }

    private func root(durable: Bool) -> URL {
        let base = durable
            ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            : FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appending(path: "retro", directoryHint: .isDirectory).appending(path: folder, directoryHint: .isDirectory)
    }

    func save<T: Encodable>(_ value: T, as key: String, durable: Bool = false) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let url = root(durable: durable).appending(path: key + ".json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func load<T: Decodable>(_ type: T.Type, _ key: String, durable: Bool = false) -> T? {
        let url = root(durable: durable).appending(path: key + ".json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Sign-out. Reads go; anything durable stays in its own folder and is sent only when this user signs in again,
    /// because it is their record and not a cache.
    func wipeCaches() {
        try? FileManager.default.removeItem(at: root(durable: false))
    }

    func durableURL(_ key: String) -> URL {
        root(durable: true).appending(path: key + ".json")
    }

    func cacheDirectory(_ key: String) -> URL { root(durable: false).appending(path: key, directoryHint: .isDirectory) }
}
