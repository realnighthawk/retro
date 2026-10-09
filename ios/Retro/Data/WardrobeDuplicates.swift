import Foundation
import Vision

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
                for photo in photos.prefix(40) {
                    try Task.checkCancellation()
                    let other = try printFor(photo.bytes)
                    var distance: Float = 0
                    try original.computeDistance(&distance, to: other)
                    guard distance.isFinite, distance >= 0 else { throw WardrobeWriteError("Image comparison returned an invalid distance.") }
                    hints.append(WardrobeDuplicateHint(photo: photo, distance: distance))
                }
                return Array(hints.sorted { $0.distance < $1.distance }.prefix(3))
            } onCancel: { request.cancel() }
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
