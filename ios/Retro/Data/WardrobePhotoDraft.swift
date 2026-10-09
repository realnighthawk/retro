import Foundation

struct WardrobePhotoBytes: Codable, Sendable, Equatable {
    let id: String
    let checksum: String
    let size: Int
}
struct WardrobePhotoEdit: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let original: WardrobePhotoBytes
    let chosen: WardrobePhotoBytes
}
struct WardrobePhotoDraft: Codable, Identifiable {
    let id: String
    let garment: WardrobeGarment
    let retained: [String]
    let photos: [WardrobePhotoEdit]
    let updatedAt: Date
    var sources: [WardrobePhotoBytes] { photos.flatMap { [$0.original, $0.chosen] } }
}
struct WardrobePhotoManifest: Codable {
    let version: Int
    let batches: [WardrobePhotoBatch]
    let drafts: [WardrobePhotoDraft]
}
