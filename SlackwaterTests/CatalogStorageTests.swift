import XCTest
@testable import Slackwater

final class CatalogStorageTests: XCTestCase {
    private var storage: CatalogStorage!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        storage = CatalogStorage(root: root, bundleDirectory: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
    }

    override func tearDownWithError() throws {
        if let root = storage?.root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    private func copyCatalogs(to directory: URL) throws {
        for resource in CatalogSnapshot.resources {
            try FileManager.default.copyItem(
                at: XCTUnwrap(Bundle.main.url(forResource: resource, withExtension: "json")),
                to: directory.appendingPathComponent(resource + ".json"))
        }
    }

    private func commitBundle(batch: UUID) throws -> StoredCatalogGeneration {
        let staging = try storage.prepareStaging(for: batch)
        try copyCatalogs(to: staging)
        let etags = Dictionary(uniqueKeysWithValues: CatalogSnapshot.resources.map { ($0, "etag-\($0)") })
        return try storage.commit(batch: batch, etags: etags, active: nil)
    }

    func testCommitPublishesValidatedGenerationAndMetadata() throws {
        let batch = UUID()
        let staging = try storage.prepareStaging(for: batch)
        try copyCatalogs(to: staging)
        let etags = Dictionary(uniqueKeysWithValues: CatalogSnapshot.resources.map { ($0, "etag-\($0)") })

        let committed = try storage.commit(batch: batch, etags: etags, active: nil)

        XCTAssertEqual(try String(contentsOf: storage.currentURL, encoding: .utf8), committed.name)
        XCTAssertEqual(try storage.loadActive(active: nil)?.metadata.etags, etags)
        XCTAssertEqual(try storage.loadActive(active: nil)?.snapshot.byID.count,
                       committed.snapshot.byID.count)
    }

    func testInvalidStagingNeverReplacesCurrent() throws {
        let original = try commitBundle(batch: UUID())
        let badBatch = UUID()
        let staging = try storage.prepareStaging(for: badBatch)
        try copyCatalogs(to: staging)
        try Data("broken".utf8).write(to: staging.appendingPathComponent("stations.json"))

        XCTAssertThrowsError(try storage.commit(batch: badBatch, etags: [:], active: original.snapshot))
        XCTAssertEqual(try String(contentsOf: storage.currentURL, encoding: .utf8), original.name)
    }

    func testOrphanGenerationDoesNotChangeCurrent() throws {
        let original = try commitBundle(batch: UUID())
        let orphan = storage.root.appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)

        XCTAssertEqual(try storage.loadActive(active: nil)?.name, original.name)
    }

    func testCorruptPointerIsNamedError() throws {
        try FileManager.default.createDirectory(at: storage.root, withIntermediateDirectories: true)
        try Data("../outside".utf8).write(to: storage.currentURL)
        XCTAssertThrowsError(try storage.activeDirectory()) { error in
            XCTAssertEqual(error as? CatalogStorageError, .invalidCurrentPointer)
        }
    }

    func testCorruptMetadataIsNamedError() throws {
        let committed = try commitBundle(batch: UUID())
        try Data("broken".utf8).write(to: committed.directory.appendingPathComponent("metadata.json"))
        XCTAssertThrowsError(try storage.loadActive(active: nil)) { error in
            XCTAssertEqual(error as? CatalogStorageError, .invalidMetadata)
        }
    }

    func testLocatorPinsOneDirectoryForAllReads() throws {
        let active = try commitBundle(batch: UUID())
        var directories: [URL] = []
        let result: String? = CatalogFileLocator(storage: storage).load { directory in
            directories += [directory, directory]
            _ = try Data(contentsOf: directory.appendingPathComponent("stations.json"))
            _ = try Data(contentsOf: directory.appendingPathComponent("currents.json"))
            return "ok"
        }
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(Set(directories), [active.directory])
    }

    func testMissingRecordDoesNotResurrectBundledRecord() throws {
        _ = try commitBundle(batch: UUID())
        var attempts = 0
        let result: String? = CatalogFileLocator(storage: storage).load { _ in
            attempts += 1
            return nil
        }
        XCTAssertNil(result)
        XCTAssertEqual(attempts, 1)
    }

    func testFailedPinnedReadRetriesNewGenerationThenBundle() throws {
        let old = try commitBundle(batch: UUID())
        var attempted: [URL] = []
        let locator = CatalogFileLocator(storage: storage)
        let result: String? = locator.load { directory in
            attempted.append(directory)
            if directory == old.directory {
                _ = try self.commitBundle(batch: UUID())
                try FileManager.default.removeItem(at: old.directory)
                throw CatalogStorageError.missingGeneration(old.name)
            }
            return directory.lastPathComponent
        }
        XCTAssertEqual(result, try storage.activeDirectory()?.lastPathComponent)
        XCTAssertEqual(attempted.count, 2)
    }

    func testFailedActiveAndRetryReadsFallBackToBundle() throws {
        let active = try commitBundle(batch: UUID())
        let result: URL? = CatalogFileLocator(storage: storage).load { directory in
            if directory == storage.bundleDirectory { return directory }
            throw CatalogStorageError.missingGeneration(active.name)
        }
        XCTAssertEqual(result, storage.bundleDirectory)
    }
}
