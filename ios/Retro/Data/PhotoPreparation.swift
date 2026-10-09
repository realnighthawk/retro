import Foundation
import ImageIO
import UIKit
import Vision
import CoreImage

struct WardrobePreparedPhoto: Identifiable, Equatable, Sendable {
    var id = UUID()
    let original: Data
    var chosen: Data
    var cutouts: [Data] = []
}

enum PhotoPreparation {
    static func normalize(_ data: Data, edge: Int = 2048) throws -> Data {
        guard !data.isEmpty, data.count <= 64 * 1024 * 1024, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int, let h = properties[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, Int64(w) * Int64(h) <= 24_000_000 else { throw WardrobeWriteError("Choose a readable photo of at most 24 megapixels.") }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: edge, kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw WardrobeWriteError("This photo could not be decoded.") }
        return try jpeg(image)
    }
    static func display(_ data: Data) -> UIImage? {
        guard !data.isEmpty, data.count <= 12 * 1024 * 1024, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int, let h = properties[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, Int64(w) * Int64(h) <= 24_000_000,
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
    static func jpeg(_ image: CGImage) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let size = CGSize(width: image.width, height: image.height)
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }
        guard let bytes = rendered.jpegData(compressionQuality: 0.88), !bytes.isEmpty, bytes.count <= 12 * 1024 * 1024 else { throw WardrobeWriteError("The exported photo exceeds 12 MiB.") }
        return bytes
    }
    static func labelText(_ data: Data) async throws -> String {
        let task = Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try VNImageRequestHandler(data: data).perform([request])
                try Task.checkCancellation()
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            } onCancel: { request.cancel() }
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    static func cutouts(_ data: Data) async throws -> [Data] {
        let task = Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(data: data)
            return try await withTaskCancellationHandler {
                try Task.checkCancellation(); try handler.perform([request])
                guard let observation = request.results?.first else { throw WardrobeWriteError("No foreground subject was found. Keep the original photo.") }
                // shortcut: preview at most six subjects; add a tap-to-select mask UI if crowded garment photos become common.
                let subjects = observation.allInstances.prefix(6)
                var output: [Data] = []
                let context = CIContext()
                for subject in subjects {
                    try Task.checkCancellation()
                    let buffer = try observation.generateMaskedImage(ofInstances: IndexSet(integer: subject), from: handler, croppedToInstancesExtent: true)
                    let image = CIImage(cvPixelBuffer: buffer)
                    guard let cg = context.createCGImage(image, from: image.extent) else { continue }
                    output.append(try jpeg(cg))
                }
                guard !output.isEmpty else { throw WardrobeWriteError("No useful cutout was found. Keep the original photo.") }
                return output
            } onCancel: { request.cancel() }
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
