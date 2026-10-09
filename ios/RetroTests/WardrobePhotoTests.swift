import XCTest
import ImageIO
import UIKit
@testable import Retro

@MainActor final class WardrobePhotoTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "wardrobe"))
        return try Data(contentsOf: url)
    }
    private func garment() throws -> WardrobeGarment {
        try JSONDecoder().decode(WardrobePage<WardrobeGarment>.self, from: fixture("inventory")).items[0]
    }

    func testPhotoDraftRelaunchRestoresOriginalChoiceAndAtomicallyMovesToQueue() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = Engine(owner: "A", api: RetroAPI(baseURL: "https://photo.test/api/v1"), currentUser: { "A" }, token: { _ in "token" })
        let writes = WardrobeWrites(file: root.appending(path: "writes.json"), stillOwner: { true }, send: { _, _ in .ok(true) })
        let folder = root.appending(path: "sources")
        let photos = WardrobePhotos(engine: engine, writes: writes, directory: folder)
        let id = UUID().uuidString.lowercased()
        let original = Data("normalized original".utf8), chosen = Data("chosen cutout".utf8)
        let first = WardrobePreparedPhoto(original: original, chosen: chosen)
        let second = WardrobePreparedPhoto(original: Data("second".utf8), chosen: Data("second".utf8))
        try photos.saveDraft(id: id, garment: garment(), retained: [], photos: [second, first])
        let stored = photos.drafts[0]
        XCTAssertEqual(stored.photos[0].original.id, stored.photos[0].chosen.id)
        for file in stored.sources {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-172800)], ofItemAtPath: folder.appending(path: "\(file.id).jpg").path)
        }
        let restored = WardrobePhotos(engine: engine, writes: writes, directory: folder)
        let loaded = try await restored.loadDraft(id)
        XCTAssertEqual(loaded.map(\.id), [second.id, first.id])
        XCTAssertEqual(loaded[1].original, original); XCTAssertEqual(loaded[1].chosen, chosen)
        XCTAssertTrue(loaded[1].cutouts.isEmpty)
        try restored.saveDraft(id: id, garment: garment(), retained: [], photos: loaded)
        XCTAssertEqual(restored.drafts[0].photos.map { $0.chosen.id }, stored.photos.map { $0.chosen.id })
        try restored.acceptDraft(id)
        XCTAssertTrue(restored.drafts.isEmpty)
        XCTAssertEqual(restored.batches[0].photos.map(\.id), stored.photos.map { $0.chosen.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appending(path: "\(stored.photos[1].original.id).jpg").path))
        XCTAssertThrowsError(try restored.acceptDraft(id))
        let relaunched = WardrobePhotos(engine: engine, writes: writes, directory: folder)
        XCTAssertTrue(relaunched.drafts.isEmpty); XCTAssertEqual(relaunched.batches.count, 1)
        XCTAssertEqual(relaunched.batches[0].photos.map(\.prepareKey), restored.batches[0].photos.map(\.prepareKey))
    }

    func testFailedPhotoDraftHandoffPreservesDraftAndBothSourceFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = Engine(owner: "A", api: RetroAPI(baseURL: "https://photo.test/api/v1"), currentUser: { "A" }, token: { _ in "token" })
        let writes = WardrobeWrites(file: root.appending(path: "writes.json"), stillOwner: { true }, send: { _, _ in .ok(true) })
        let folder = root.appending(path: "sources"), file = folder.appending(path: "jobs.json"), backup = root.appending(path: "manifest-backup.json")
        let photos = WardrobePhotos(engine: engine, writes: writes, directory: folder)
        let id = UUID().uuidString.lowercased()
        try photos.saveDraft(id: id, garment: garment(), retained: [], photos: [WardrobePreparedPhoto(original: Data("original".utf8), chosen: Data("cutout".utf8))])
        let sources = photos.drafts[0].sources
        try FileManager.default.moveItem(at: file, to: backup)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        try Data("write obstruction".utf8).write(to: file.appending(path: "child"))
        XCTAssertThrowsError(try photos.acceptDraft(id))
        XCTAssertEqual(photos.drafts.count, 1); XCTAssertTrue(photos.batches.isEmpty)
        for source in sources { XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "\(source.id).jpg").path)) }
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: backup, to: file)
        let restored = WardrobePhotos(engine: engine, writes: writes, directory: folder)
        XCTAssertEqual(restored.drafts.count, 1); XCTAssertTrue(restored.batches.isEmpty)
    }

    func testDamagedPhotoDraftCannotBeAcceptedAndOwnerCannotResumeIt() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var owner = "A"
        let engine = Engine(owner: "A", api: RetroAPI(baseURL: "https://photo.test/api/v1"), currentUser: { owner }, token: { _ in "token" })
        let writes = WardrobeWrites(file: root.appending(path: "writes.json"), stillOwner: { owner == "A" }, send: { _, _ in .ok(true) })
        let folder = root.appending(path: "sources")
        let photos = WardrobePhotos(engine: engine, writes: writes, directory: folder)
        let id = UUID().uuidString.lowercased()
        try photos.saveDraft(id: id, garment: garment(), retained: [], photos: [WardrobePreparedPhoto(original: Data("good".utf8), chosen: Data("good".utf8))])
        let manifest = try Data(contentsOf: folder.appending(path: "jobs.json"))
        let source = folder.appending(path: "\(photos.drafts[0].photos[0].chosen.id).jpg")
        try Data("evil".utf8).write(to: source)
        XCTAssertThrowsError(try photos.acceptDraft(id))
        do { _ = try await photos.loadDraft(id); XCTFail("Changed bytes must not load") } catch { }
        XCTAssertEqual(photos.drafts.count, 1); XCTAssertTrue(photos.batches.isEmpty); XCTAssertTrue(writes.items.isEmpty)
        XCTAssertEqual(try Data(contentsOf: folder.appending(path: "jobs.json")), manifest)
        try Data("good".utf8).write(to: source)
        owner = "B"
        do { _ = try await photos.loadDraft(id); XCTFail("An old owner must not resume a draft") } catch { }
        XCTAssertThrowsError(try photos.discardDraft(id)); XCTAssertThrowsError(try photos.acceptDraft(id))
    }

    func testReferenceOnlyDraftChecksLiveBaselineAndQueuesOnlyReviewedReferences() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); PhotoProtocol.handle = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PhotoProtocol.self]
        let engine = Engine(owner: "A", api: RetroAPI(baseURL: "https://photo.test/api/v1", session: URLSession(configuration: config)), currentUser: { "A" }, token: { _ in "token" })
        let writes = WardrobeWrites(file: root.appending(path: "writes.json"), stillOwner: { true }, send: { _, _ in .ok(true) })
        let folder = root.appending(path: "sources")
        let photos = WardrobePhotos(engine: engine, writes: writes, directory: folder)
        let original = try garment(), id = UUID().uuidString.lowercased()
        try photos.saveDraft(id: id, garment: original, retained: [], photos: [])
        try photos.acceptDraft(id)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        fields["media_ids"] = []; fields["version"] = original.version + 1
        let live = try JSONDecoder().decode(WardrobeGarment.self, from: JSONSerialization.data(withJSONObject: fields))
        var calls = 0
        PhotoProtocol.handle = { request in
            calls += 1; XCTAssertTrue(request.request.url!.path.hasSuffix("garments_get"))
            request.finish(200, try! JSONEncoder().encode(WardrobeGarmentResult(garment: live)))
        }
        await photos.step()
        XCTAssertTrue(photos.batches[0].blocked); XCTAssertTrue(writes.items.isEmpty)
        try photos.review(id, current: live, retained: [])
        await photos.step()
        XCTAssertEqual(calls, 2); XCTAssertEqual(writes.items.count, 1)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: writes.items[0].body) as? [String: Any])
        XCTAssertEqual((body["expected_version"] as? NSNumber)?.int64Value, live.version)
        XCTAssertEqual((body["patch"] as? [String: Any])?.keys.sorted(), ["media_ids"])
        XCTAssertEqual((body["patch"] as? [String: Any])?["media_ids"] as? [String], [])
    }

    func testLegacyPhotoJobsMigrateAndUnknownManifestVersionPreservesSources() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = Engine(owner: "A", api: RetroAPI(baseURL: "https://photo.test/api/v1"), currentUser: { "A" }, token: { _ in "token" })
        let writes = WardrobeWrites(file: root.appending(path: "writes.json"), stillOwner: { true }, send: { _, _ in .ok(true) })
        let folder = root.appending(path: "sources"), file = folder.appending(path: "jobs.json")
        let photos = WardrobePhotos(engine: engine, writes: writes, directory: folder)
        try photos.stage(garment: garment(), retained: [], images: [Data("bytes".utf8)])
        try JSONEncoder().encode(photos.batches).write(to: file)
        let legacy = WardrobePhotos(engine: engine, writes: writes, directory: folder)
        XCTAssertNil(legacy.problem); XCTAssertEqual(legacy.batches.count, 1)
        try legacy.discard(legacy.batches[0].id)
        XCTAssertEqual(try JSONDecoder().decode(WardrobePhotoManifest.self, from: Data(contentsOf: file)).version, 1)
        let orphan = folder.appending(path: "33333333-3333-4333-8333-333333333333.jpg")
        try Data("preserve".utf8).write(to: orphan)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-172800)], ofItemAtPath: orphan.path)
        let unknown = try JSONEncoder().encode(WardrobePhotoManifest(version: 2, batches: [], drafts: []))
        try unknown.write(to: file)
        let unreadable = WardrobePhotos(engine: engine, writes: writes, directory: folder)
        XCTAssertNotNil(unreadable.problem); XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertEqual(try Data(contentsOf: file), unknown)
    }

    func testWireMediaAndOnlyContractPaths() throws {
        let media = try JSONDecoder().decode(WardrobeMediaResult.self, from: fixture("media")).media
        XCTAssertEqual(media.version, 9007199254740993)
        XCTAssertEqual(WardrobeMediaPath.path(id: media.id, variant: "thumbnail"), "/media/\(media.id)/content?variant=thumbnail")
        XCTAssertNil(WardrobeMediaPath.path(id: "https://evil.test/photo"))
        XCTAssertNil(WardrobeMediaPath.path(id: "../private"))
        XCTAssertNil(WardrobeMediaPath.path(id: media.id, variant: "source&next=https://evil.test"))
    }

    func testNormalizationStripsMetadataAndInvalidSuggestionsCannotApply() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 20)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 30, height: 20))
        }
        let bytes = try PhotoPreparation.normalize(XCTUnwrap(image.pngData()))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.jpeg")
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertThrowsError(try PhotoPreparation.normalize(Data([1, 2, 3])))
        XCTAssertThrowsError(try WardrobeAssistedDraft(name: "Shirt", category: "invented", subtype: nil, colours: [], notes: nil).validate())
        XCTAssertThrowsError(try WardrobeAssistedDraft(name: String(repeating: "é", count: 51), category: "top", subtype: nil, colours: [], notes: nil).validate())
        XCTAssertThrowsError(try WardrobeAssistedDraft(name: "Shirt", category: "top", subtype: nil, colours: ["blue", "blue"], notes: nil).validate())
    }

    func testLostAttachmentRelaunchRetainsBytesAndReplaysFrozenVersion() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); PhotoProtocol.handle = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PhotoProtocol.self]
        let session = URLSession(configuration: config)
        let engine = Engine(owner: "A", api: RetroAPI(baseURL: "https://photo.test/retro/api/v1", session: session, binarySession: session), currentUser: { "A" }, token: { _ in "A-token" })
        let queueFile = root.appending(path: "writes.json")
        let writes = WardrobeWrites(file: queueFile, stillOwner: { true }) { op, body in
            let result: Api<WardrobeGarmentResult> = await engine.callFrozen(op, body: body); return result.map { _ in true }
        }
        let photos = WardrobePhotos(engine: engine, writes: writes, directory: root.appending(path: "sources"), cacheDirectory: root.appending(path: "cache"))
        let garment = try garment()
        let bytes = Data("immutable selected JPEG fixture bytes".utf8)
        try photos.stage(garment: garment, retained: garment.mediaIDs ?? [], images: [bytes])
        let local = photos.batches[0].photos[0]
        let source = root.appending(path: "sources/\(local.id).jpg")
        var state = "awaiting_upload"
        var firstAttachment: Data?
        var replay: Data?
        var attachments = 0
        let garmentResult = try JSONEncoder().encode(WardrobeGarmentResult(garment: garment))
        PhotoProtocol.handle = { request in
            Task { @MainActor in
                let path = request.request.url!.path
                if path.hasSuffix("/content") {
                    XCTAssertEqual(request.request.httpMethod, "PUT")
                    XCTAssertEqual(request.body(), bytes)
                    XCTAssertEqual(request.request.value(forHTTPHeaderField: "Authorization"), "Bearer A-token")
                    state = "processing"
                }
                if path.hasSuffix("garments_update") {
                    attachments += 1
                    if attachments == 1 { firstAttachment = request.body(); request.finish(503, Data()); return }
                    replay = request.body(); request.finish(200, garmentResult); return
                }
                if path.hasSuffix("garments_get") { request.finish(200, garmentResult); return }
                let media = WardrobeMedia(id: local.id, version: 2, checksum: local.checksum, sizeBytes: Int64(bytes.count), mimeType: "image/jpeg", state: state,
                                          width: nil, height: nil, error: nil, uploadPath: "https://evil.test/never-used", displayPath: nil, thumbnailPath: nil)
                request.finish(200, try! JSONEncoder().encode(WardrobeMediaResult(media: media)))
            }
        }
        await photos.step()
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertNil(photos.batches[0].attachment)
        state = "ready"
        await photos.step()
        let original = try XCTUnwrap(photos.batches[0].attachment)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        XCTAssertEqual((fields["expected_version"] as? NSNumber)?.int64Value, garment.version)
        let delivered = await writes.drain()
        XCTAssertFalse(delivered)
        XCTAssertEqual(firstAttachment, original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let restoredWrites = WardrobeWrites(file: queueFile, stillOwner: { true }) { op, body in
            let result: Api<WardrobeGarmentResult> = await engine.callFrozen(op, body: body); return result.map { _ in true }
        }
        let restored = WardrobePhotos(engine: engine, writes: restoredWrites, directory: root.appending(path: "sources"), cacheDirectory: root.appending(path: "cache"))
        await restored.step()
        let acknowledged = await restoredWrites.drain(force: true)
        XCTAssertTrue(acknowledged)
        restored.reconcile()
        XCTAssertEqual(replay, original)
        XCTAssertTrue(restored.batches.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testOldStagingOrphansArePrunedOnlyWithReadableIntentAndQueuedBytesStay() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = Engine(owner: "A", api: RetroAPI(baseURL: "https://photo.test/api/v1"), currentUser: { "A" }, token: { _ in "token" })
        let writes = WardrobeWrites(file: root.appending(path: "writes.json"), stillOwner: { true }, send: { _, _ in .ok(true) })
        let folder = root.appending(path: "sources")
        let photos = WardrobePhotos(engine: engine, writes: writes, directory: folder)
        try photos.stage(garment: garment(), retained: [], images: [Data("bytes".utf8)])
        let queued = folder.appending(path: "\(photos.batches[0].photos[0].id).jpg")
        let orphan = folder.appending(path: "33333333-3333-4333-8333-333333333333.jpg")
        try Data("orphan".utf8).write(to: orphan)
        let old = Date().addingTimeInterval(-172800)
        for file in [queued, orphan] { try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path) }
        _ = WardrobePhotos(engine: engine, writes: writes, directory: folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: queued.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        try Data("orphan".utf8).write(to: orphan)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: orphan.path)
        try Data("damaged".utf8).write(to: folder.appending(path: "jobs.json"))
        let unreadable = WardrobePhotos(engine: engine, writes: writes, directory: folder)
        XCTAssertNotNil(unreadable.problem)
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testExplicitPhotoRetryReplacesCachedBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); PhotoProtocol.handle = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PhotoProtocol.self]
        let session = URLSession(configuration: config)
        let engine = Engine(owner: "A", api: RetroAPI(baseURL: "https://photo.test/api/v1", session: session, binarySession: session), currentUser: { "A" }, token: { _ in "token" })
        let writes = WardrobeWrites(file: root.appending(path: "writes.json"), stillOwner: { true }, send: { _, _ in .ok(true) })
        let cache = root.appending(path: "cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let id = "33333333-3333-4333-8333-333333333333"
        let file = cache.appending(path: "\(id)-thumbnail.jpg")
        try Data("unreadable cached bytes".utf8).write(to: file)
        let photos = WardrobePhotos(engine: engine, writes: writes, directory: root.appending(path: "sources"), cacheDirectory: cache)
        let fresh = Data("fresh photo bytes from fake transport".utf8)
        PhotoProtocol.handle = { $0.finish(200, fresh) }
        let result = await photos.image(id, variant: "thumbnail", reload: true)
        if case .ok(let data) = result { XCTAssertEqual(data, fresh) } else { XCTFail("Retry should fetch fresh bytes") }
        XCTAssertEqual(try Data(contentsOf: file), fresh)
    }

    func testLateBinaryResponseDoesNotEnterAnotherAccountsCache() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); PhotoProtocol.handle = nil }
        var owner = "A"
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PhotoProtocol.self]
        let session = URLSession(configuration: config)
        let engine = Engine(owner: "A", api: RetroAPI(baseURL: "https://photo.test/api/v1", session: session, binarySession: session), currentUser: { owner }, token: { _ in "A-token" })
        let writes = WardrobeWrites(file: root.appending(path: "writes.json"), stillOwner: { owner == "A" }, send: { _, _ in .ok(true) })
        let photos = WardrobePhotos(engine: engine, writes: writes, directory: root.appending(path: "sources"), cacheDirectory: root.appending(path: "cache"))
        PhotoProtocol.handle = { request in Task { @MainActor in owner = "B"; request.finish(200, Data("image".utf8)) } }
        let id = "33333333-3333-4333-8333-333333333333"
        let result = await photos.image(id, variant: "thumbnail")
        if case .unauthorized = result {} else { XCTFail("Old owner response must be rejected") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "cache/\(id)-thumbnail.jpg").path))
    }

    func testChangedPhotoReferencesRequireExplicitReviewAndKeepReadyBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); PhotoProtocol.handle = nil }
        let original = try garment()
        let result = try JSONEncoder().encode(WardrobeGarmentResult(garment: original))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: result) as? [String: Any])
        var changed = try XCTUnwrap(object["garment"] as? [String: Any]); changed["media_ids"] = []
        object["garment"] = changed
        let changedData = try JSONSerialization.data(withJSONObject: object)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PhotoProtocol.self]
        let session = URLSession(configuration: config)
        let engine = Engine(owner: "A", api: RetroAPI(baseURL: "https://photo.test/api/v1", session: session, binarySession: session), currentUser: { "A" }, token: { _ in "token" })
        let writes = WardrobeWrites(file: root.appending(path: "writes.json"), stillOwner: { true }, send: { _, _ in .ok(true) })
        let photos = WardrobePhotos(engine: engine, writes: writes, directory: root.appending(path: "sources"), cacheDirectory: root.appending(path: "cache"))
        try photos.stage(garment: original, retained: original.mediaIDs ?? [], images: [Data("bytes".utf8)])
        let local = photos.batches[0].photos[0]
        PhotoProtocol.handle = { request in
            if request.request.url!.path.hasSuffix("garments_get") { request.finish(200, changedData) }
            else {
                let media = WardrobeMedia(id: local.id, version: 3, checksum: local.checksum, sizeBytes: Int64(local.size), mimeType: "image/jpeg", state: "ready", width: nil, height: nil, error: nil, uploadPath: "unused", displayPath: nil, thumbnailPath: nil)
                request.finish(200, try! JSONEncoder().encode(WardrobeMediaResult(media: media)))
            }
        }
        await photos.step()
        XCTAssertTrue(photos.batches[0].blocked)
        XCTAssertTrue(writes.items.isEmpty)
        let current = try JSONDecoder().decode(WardrobeGarmentResult.self, from: changedData).garment
        try photos.review(photos.batches[0].id, current: current, retained: [])
        await photos.step()
        XCTAssertEqual(writes.items.count, 1)
        XCTAssertEqual(photos.batches[0].photos[0].id, local.id, "Review reuses ready media rather than allocating another object")
    }
}

private final class PhotoProtocol: URLProtocol, @unchecked Sendable {
    static var handle: ((PhotoProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handle?(self) }
    override func stopLoading() {}
    func body() -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var bytes = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; data.append(contentsOf: bytes.prefix(n)) }
        return data
    }
    func finish(_ code: Int, _ data: Data) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
}
