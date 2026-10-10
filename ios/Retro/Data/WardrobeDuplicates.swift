import CryptoKit
import Foundation
import Vision

// A candidate is one active garment with a primary photo, as the complete inventory reports it at
// scan time. Its version and media identity travel with the hint so applying one needs a fresh review.
struct WardrobeDuplicateCandidate: Sendable, Equatable {
    let id: String
    let name: String
    let version: Int64
    let mediaID: String
}
// Which candidates can be compared from this phone's cache and which need a bounded fetch.
struct WardrobeDuplicatePlan: Sendable {
    let ready: [WardrobeDuplicatePhoto]
    let fetch: [WardrobeDuplicateCandidate]
    let overBudget: Int
    var planned: Int { ready.count + fetch.count }
}
// One scan: what was actually compared, what was not, and the source photo it belongs to. A hint is
// only applicable while the same source bytes are still the draft's photo.
struct WardrobeDuplicateScan: Sendable {
    let hints: [WardrobeDuplicateHint]
    let sourceChecksum: String
    let revision: Int
    let activeGarments: Int
    let indexedGarments: Int
    let totalMatches: Int64?
    let complete: Bool
    let compared: Int
    let missingPhotos: Int
    let unchecked: Int
    var readProblem: String? = nil
    var summary: String {
        if let readProblem {
            return "The inventory could not be read, so nothing was compared. \(readProblem) You can still create a garment."
        }
        var parts = ["Compared \(compared) photos from \(indexedGarments) of \(activeGarments) active garments at this time.",
                     "\(missingPhotos) \(missingPhotos == 1 ? "garment has" : "garments have") no photo and \(unchecked) \(unchecked == 1 ? "was" : "were") not checked in this scan.",
                     "The closest matches are photos to review, never a duplicate verdict, and a match is only applied after a fresh record check."]
        if !complete { parts.append("The inventory index was cut short (\(indexedGarments) of \(totalMatches.map(String.init) ?? "unknown") garments), so other pages were not checked.") }
        return parts.joined(separator: " ")
    }
    // A hint from this scan may only be applied while the same source bytes and comparison revision apply.
    func matches(source: Data) -> Bool {
        revision == WardrobeDuplicates.revision && sourceChecksum == WardrobeDuplicates.checksum(source)
    }
}

struct WardrobeDuplicatePhoto: Sendable {
    let id: String
    let name: String
    let version: Int64
    let mediaID: String
    let bytes: Data
}
struct WardrobeDuplicateHint: Identifiable, Sendable {
    let photo: WardrobeDuplicatePhoto
    let distance: Float
    var id: String { photo.id }
}
enum WardrobeDuplicates {
    static let revision = Int(VNGenerateImageFeaturePrintRequestRevision2)
    static let hintLimit = 3
    static let photoBudget = 120
    static let indexLimit = 2000
    static let pageLimit = 200

    static func checksum(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    // Cached thumbnails are free, so they are all used first; the remaining budget bounds the network
    // fetches. Everything over budget is reported, never silently dropped.
    static func plan(_ candidates: [WardrobeDuplicateCandidate], budget: Int = photoBudget, cached: (String) -> Data?) -> WardrobeDuplicatePlan {
        var ready: [WardrobeDuplicatePhoto] = [], fetch: [WardrobeDuplicateCandidate] = []
        var overBudget = 0, bytes = 16 * 1024 * 1024
        for candidate in candidates {
            if let data = cached(candidate.mediaID), data.count <= bytes {
                bytes -= data.count
                ready.append(WardrobeDuplicatePhoto(id: candidate.id, name: candidate.name, version: candidate.version, mediaID: candidate.mediaID, bytes: data))
            } else if fetch.count < budget {
                fetch.append(candidate)
            } else {
                overBudget += 1
            }
        }
        return WardrobeDuplicatePlan(ready: ready, fetch: fetch, overBudget: overBudget)
    }

    static func compare(_ source: Data, photos: [WardrobeDuplicatePhoto]) async throws -> [WardrobeDuplicateHint] {
        let task = Task.detached(priority: .userInitiated) {
            let request = VNGenerateImageFeaturePrintRequest()
            // Pin the revision; comparisons are ephemeral and never reused across images or OS revisions.
            request.revision = VNGenerateImageFeaturePrintRequestRevision2
            request.imageCropAndScaleOption = .scaleFit
            return try await withTaskCancellationHandler {
                func printFor(_ bytes: Data) throws -> VNFeaturePrintObservation {
                    try Task.checkCancellation()
                    try VNImageRequestHandler(data: PhotoPreparation.normalize(bytes, edge: 512)).perform([request])
                    guard let result = request.results?.first else { throw WardrobeWriteError("This photo could not be compared.") }
                    return result
                }
                let original = try printFor(source)
                var hints: [WardrobeDuplicateHint] = []
                for photo in photos {
                    try Task.checkCancellation()
                    let other = try printFor(photo.bytes)
                    var distance: Float = 0
                    try original.computeDistance(&distance, to: other)
                    guard distance.isFinite, distance >= 0 else { throw WardrobeWriteError("Image comparison returned an invalid distance.") }
                    hints.append(WardrobeDuplicateHint(photo: photo, distance: distance))
                }
                return Array(hints.sorted { $0.distance < $1.distance }.prefix(hintLimit))
            } onCancel: { request.cancel() }
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
