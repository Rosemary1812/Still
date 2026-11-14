import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import ContactSheet

final class AlbumImportTests: XCTestCase {
    private func png() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 12, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.setColor(NSColor(calibratedRed: 0.1, green: 0.4, blue: 0.8, alpha: 1), atX: 4, y: 4)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
    @MainActor func testImportedFilesAndAnnotationsSurviveSourceRemovalAndReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("旅行 照片.png")
        let original = try png()
        try original.write(to: source)
        let media = root.appendingPathComponent("Imports")
        let repository = PhotoRepository(importsURL: media, observeLibrary: false)
        let id = try await repository.importFile(source)
        let duplicate = try await repository.importFile(source)
        XCTAssertEqual(id, duplicate)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: media.path).count, 1)
        var store: LibraryStore? = try LibraryStore(storeURL: root.appendingPathComponent("library.store"))
        let first = try XCTUnwrap(store?.createAlbum(name: "第一本", ids: [id, duplicate]))
        _ = store?.createAlbum(name: "第二本", ids: [id])
        XCTAssertEqual(store?.orderedIDs(album: first), [id])
        store?.saveAnnotation(id: id, title: "湖边", description: "第一行\n\n风停下来的时候。", date: nil, location: "")
        XCTAssertNil(store?.error)
        store = nil
        try FileManager.default.removeItem(at: source)
        let restored = try LibraryStore(storeURL: root.appendingPathComponent("library.store"))
        XCTAssertEqual(restored.albums.count, 2)
        XCTAssertTrue(restored.albums.allSatisfy { restored.orderedIDs(album: $0) == [id] })
        XCTAssertEqual(restored.annotation(id: id)?.descriptionText, "第一行\n\n风停下来的时候。")
        let reopenedRepository = PhotoRepository(importsURL: media, observeLibrary: false)
        let image = await reopenedRepository.loadImage(id: id, size: CGSize(width: 100, height: 100))
        XCTAssertNotNil(image)
        let stored = try Data(contentsOf: media.appendingPathComponent(String(id.dropFirst(6))))
        XCTAssertEqual(stored, original)
    }
    @MainActor func testCorruptImportDoesNotCreateManagedFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PhotoRepository(importsURL: root, observeLibrary: false)
        XCTAssertThrowsError(try repository.importData(Data("not an image".utf8)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let traversal = await repository.loadImage(id: "local:../outside.png", size: CGSize(width: 10, height: 10))
        XCTAssertNil(traversal)
    }
    func testWallIncludesEveryPhotoAndHandlesSmallAlbums() {
        for count in [1, 2, 3, 4, 5, 17, 1001] {
            let rows = (0..<4).map { AlbumWallLayout.indices(count: count, row: $0) }
            XCTAssertTrue(rows.allSatisfy { !$0.isEmpty })
            XCTAssertEqual(Set(rows.flatMap { $0 }), Set(0..<count))
        }
        XCTAssertTrue(AlbumWallLayout.indices(count: 0, row: 0).isEmpty)
        XCTAssertEqual(AlbumWallLayout.phase(-0.25, period: 4), 3.75)
        XCTAssertEqual(AlbumWallLayout.phase(4.25, period: 4), 0.25)
        XCTAssertEqual(AlbumWallLayout.secondsPerTile, 17.175, accuracy: 0.01)
    }
}
