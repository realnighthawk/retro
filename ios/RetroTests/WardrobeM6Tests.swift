import XCTest
@testable import Retro

@MainActor final class WardrobeM6Tests: XCTestCase {
    private func fixture<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "wardrobe"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    func testSystemEntriesValidateParametersAndWaitForSignedInOwner() throws {
        for action in [WardrobeEntryAction.add, .search("Blue & white shirt"), .today] { XCTAssertEqual(WardrobeEntryAction(url: action.url), action) }
        for value in ["https://wardrobe/add", "org.nighthawklabs.retro://other/add", "org.nighthawklabs.retro://wardrobe/add?id=garment", "org.nighthawklabs.retro://wardrobe/search?q=a&q=b", "org.nighthawklabs.retro://wardrobe/today#garment", "org.nighthawklabs.retro://wardrobe/search?q=%0A"] { XCTAssertNil(WardrobeEntryAction(url: try XCTUnwrap(URL(string: value)))) }
        XCTAssertNil(WardrobeEntryAction(url: WardrobeEntryAction.search(String(repeating: "é", count: 51)).url))
        let entry = WardrobeEntryPoint(); entry.open(WardrobeEntryAction.add.url)
        XCTAssertNil(entry.consume(owner: false)); XCTAssertNotNil(entry.pending)
        XCTAssertEqual(entry.consume(owner: true), .add); XCTAssertNil(entry.pending)
    }
    func testReviewUsesWholePeriodCountsAndRejectsWrongDatesAndInventedTotals() throws {
        let value = try fixture("analysis", as: WardrobeAnalysis.self)
        let query = WardrobeAnalysisQuery(from: "2026-10-01", to: "2026-10-07")
        XCTAssertEqual(try value.periodSummary(query), "2 confirmed outfit events across 1 day. 0 of 1 garment had no confirmed wear in this period.")
        XCTAssertThrowsError(try value.periodSummary(WardrobeAnalysisQuery(from: "2026-10-02", to: query.to)))
        XCTAssertThrowsError(try WardrobeAnalysisQuery(from: "2026-02-30", to: query.to).validatePeriod())
        XCTAssertThrowsError(try WardrobeAnalysisQuery(from: query.to, to: query.from).validatePeriod())
        let invalid = WardrobeAnalysis(from: query.from, to: query.to, outfitEvents: 2, wearDays: 1, garments: 2, unwornGarments: 0, categories: value.categories)
        XCTAssertThrowsError(try invalid.periodSummary(query))
        let negative = WardrobeAnalysis(from: query.from, to: query.to, outfitEvents: -1, wearDays: 0, garments: 1, unwornGarments: 0, categories: value.categories)
        XCTAssertThrowsError(try negative.periodSummary(query))
    }
    func testImportRelaunchKeepsEachSourceAndIdentitySeparateFromOrdinaryDrafts() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "drafts.json")
        var owner = true
        let drafts = WardrobeSavedDrafts(file: file, stillOwner: { owner })
        let first = Data("first normalized photo".utf8), second = Data("second normalized photo".utf8)
        try drafts.addImport(first); try drafts.addImport(second)
        let saved = drafts.imports
        XCTAssertNil(drafts.garment(nil)); XCTAssertNotEqual(saved[0].entityID, saved[1].entityID)
        let restored = WardrobeSavedDrafts(file: file, stillOwner: { owner })
        XCTAssertEqual(restored.imports.map(\.entityID), saved.map(\.entityID))
        XCTAssertEqual(restored.imports.map(\.importPhoto), saved.map(\.importPhoto))
        let bytes = try await restored.importBytes(saved[0].id); XCTAssertEqual(bytes, first)
        try restored.remove(saved[0].id)
        let remaining = try await restored.importBytes(saved[1].id); XCTAssertEqual(remaining, second)
        let source = file.deletingPathExtension().appending(path: "import-photos/\(saved[1].importPhoto!.id).jpg")
        let manifest = try Data(contentsOf: file)
        try Data(repeating: 0, count: second.count).write(to: source)
        do { _ = try await restored.importBytes(saved[1].id); XCTFail("Changed bytes must stay blocked") } catch { }
        XCTAssertEqual(try Data(contentsOf: file), manifest)
        owner = false
        XCTAssertThrowsError(try restored.remove(saved[1].id)); XCTAssertThrowsError(try restored.addImport(first))
        do { _ = try await restored.importBytes(saved[1].id); XCTFail("Old account cannot reopen import bytes") } catch { }
    }
    func testImportPhotoHandoffSurvivesRelaunchWithoutAnotherMediaID() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "drafts.json")
        let drafts = WardrobeSavedDrafts(file: file, stillOwner: { true })
        let bytes = Data("normalized photo".utf8); try drafts.addImport(bytes)
        var entry = drafts.imports[0]
        var edited = WardrobeGarmentDraft(); edited.name = "Reviewed shirt"
        let writes = WardrobeWrites(file: root.appending(path: "writes.json"), stillOwner: { true }, send: { _, _ in .ok(true) })
        var fields = try edited.fields(); fields["id"] = entry.entityID
        try writes.enqueue(operation: "garments_create", entity: entry.entityID, title: edited.name, fields: fields)
        entry.garmentDraft = edited; entry.dependency = writes.items[0]
        try drafts.put(entry); XCTAssertFalse(try entry.hasImportEdits())
        edited.notes = "Later change"; entry.garmentDraft = edited
        XCTAssertTrue(try entry.hasImportEdits())
        entry.garmentDraft = try entry.originalGarment()
        _ = await writes.drain()
        let engine = Engine(owner: "A", api: RetroAPI(baseURL: "https://photo.test/api/v1"), currentUser: { "A" }, token: { _ in "token" })
        let folder = root.appending(path: "photos")
        let photos = WardrobePhotos(engine: engine, writes: writes, directory: folder)
        let initial = try fixture("inventory", as: WardrobePage<WardrobeGarment>.self).items[0]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(initial)) as? [String: Any]); object["id"] = entry.entityID
        let garment = try JSONDecoder().decode(WardrobeGarment.self, from: JSONSerialization.data(withJSONObject: object))
        // Component handoff checks the saved media identity; live target/version checks belong to the store flow.
        try photos.saveDraft(id: entry.id, garment: garment, retained: garment.mediaIDs ?? [], photos: [WardrobePreparedPhoto(id: UUID(uuidString: entry.id)!, original: bytes, chosen: bytes)])
        entry.importMediaID = photos.drafts[0].photos[0].chosen.id; try drafts.put(entry)
        try photos.acceptDraft(entry.id)
        let restored = WardrobeSavedDrafts(file: file, stillOwner: { true })
        let jobs = WardrobePhotos(engine: engine, writes: writes, directory: folder)
        XCTAssertEqual(restored.imports[0].dependency?.id, entry.dependency?.id)
        XCTAssertEqual(restored.imports[0].importMediaID, jobs.batches[0].photos[0].id)
        XCTAssertThrowsError(try jobs.acceptDraft(entry.id)); XCTAssertEqual(jobs.batches.count, 1)
    }
    func testCorruptImportManifestIsPreservedAndDoesNotPruneItsPhotos() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "drafts.json")
        let drafts = WardrobeSavedDrafts(file: file, stillOwner: { true }); try drafts.addImport(Data("photo".utf8))
        let source = file.deletingPathExtension().appending(path: "import-photos/\(drafts.imports[0].importPhoto!.id).jpg")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-172800)], ofItemAtPath: source.path)
        try Data("broken manifest".utf8).write(to: file)
        let restored = WardrobeSavedDrafts(file: file, stillOwner: { true })
        XCTAssertNotNil(restored.problem); XCTAssertThrowsError(try restored.addImport(Data("other".utf8)))
        XCTAssertEqual(try Data(contentsOf: file), Data("broken manifest".utf8)); XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testThumbnailComparisonInputNeverFetchesMissingPhotos() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = Engine(owner: "A", api: RetroAPI(baseURL: "https://photo.test/api/v1"), currentUser: { "A" }, token: { _ in "token" })
        let writes = WardrobeWrites(file: root.appending(path: "writes.json"), stillOwner: { true }, send: { _, _ in .ok(true) })
        let cache = root.appending(path: "cache"); try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let photos = WardrobePhotos(engine: engine, writes: writes, directory: root.appending(path: "photos"), cacheDirectory: cache)
        let id = UUID().uuidString.lowercased(); XCTAssertNil(photos.cachedThumbnail(id)); XCTAssertNil(photos.cachedThumbnail("../private"))
        let bytes = Data("cached thumbnail".utf8); try bytes.write(to: cache.appending(path: "\(id)-thumbnail.jpg"))
        XCTAssertEqual(photos.cachedThumbnail(id), bytes)
    }
}
