import Foundation
import os

struct CatalogMetadata: Codable, Equatable {
    let etags: [String: String]
}

struct StoredCatalogGeneration {
    let name: String
    let directory: URL
    let metadata: CatalogMetadata
    let snapshot: CatalogSnapshot
}

enum CatalogStorageError: Error, Equatable {
    case invalidCurrentPointer
    case missingGeneration(String)
    case invalidMetadata
}

struct CatalogStorage {
    static let shared = CatalogStorage(
        root: AppGroup.container.appendingPathComponent("Catalogs", isDirectory: true),
        bundleDirectory: Bundle.main.resourceURL ?? Bundle.main.bundleURL)

    let root: URL
    let bundleDirectory: URL
    private let files = FileManager.default

    init(root: URL, bundleDirectory: URL) {
        self.root = root
        self.bundleDirectory = bundleDirectory
    }

    var currentURL: URL { root.appendingPathComponent("current") }

    func stagingDirectory(for batch: UUID) -> URL {
        root.appendingPathComponent("staging-\(batch.uuidString.lowercased())", isDirectory: true)
    }

    func prepareStaging(for batch: UUID) throws -> URL {
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = stagingDirectory(for: batch)
        try files.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    func activeDirectory() throws -> URL? {
        guard files.fileExists(atPath: currentURL.path) else { return nil }
        let name = try String(contentsOf: currentURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: name) != nil else { throw CatalogStorageError.invalidCurrentPointer }
        let directory = root.appendingPathComponent(name, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CatalogStorageError.missingGeneration(name)
        }
        return directory
    }

    func loadActive(active: CatalogSnapshot?) throws -> StoredCatalogGeneration? {
        guard let directory = try activeDirectory() else { return nil }
        let metadataURL = directory.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(CatalogMetadata.self, from: data) else {
            throw CatalogStorageError.invalidMetadata
        }
        return StoredCatalogGeneration(
            name: directory.lastPathComponent,
            directory: directory,
            metadata: metadata,
            snapshot: try CatalogSnapshot(directory: directory, active: active))
    }

    func commit(batch: UUID, etags: [String: String], active: CatalogSnapshot?) throws -> StoredCatalogGeneration {
        let staging = stagingDirectory(for: batch)
        let snapshot = try CatalogSnapshot(directory: staging, active: active)
        let metadata = CatalogMetadata(etags: etags)
        try JSONEncoder().encode(metadata).write(
            to: staging.appendingPathComponent("metadata.json"), options: .atomic)
        let name = batch.uuidString.lowercased()
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try files.moveItem(at: staging, to: directory)
        try Data(name.utf8).write(to: currentURL, options: .atomic)
        return StoredCatalogGeneration(name: name, directory: directory,
                                       metadata: metadata, snapshot: snapshot)
    }
}
