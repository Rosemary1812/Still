import XCTest
@testable import ContactSheet

final class ModelPlaybackTests: XCTestCase {
 @MainActor func testMembershipOrderAndSharedAnnotation() throws {
  let store = try LibraryStore(inMemory: true)
  let a = try XCTUnwrap(store.createAlbum(name: "Trip", ids: ["a", "b", "a", "c"]))
  let b = try XCTUnwrap(store.createAlbum(name: "Favorites", ids: ["a"]))
  XCTAssertEqual(store.orderedIDs(album: a), ["a", "b", "c"])
  store.move(id: "c", before: "a", in: a)
  XCTAssertEqual(store.orderedIDs(album: a), ["c", "a", "b"])
  store.saveAnnotation(id: "a", title: "Memory", description: "Shared", date: nil, location: "")
  store.remove(ids: ["a"], from: a)
  XCTAssertEqual(store.annotation(id: "a")?.title, "Memory")
  store.delete(album: a)
  XCTAssertEqual(store.orderedIDs(album: b), ["a"])
  XCTAssertEqual(store.annotation(id: "a")?.descriptionText, "Shared")
 }
 @MainActor func testDiskPersistence() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("library.store")
  var store: LibraryStore? = try LibraryStore(storeURL: url)
  _ = store?.createAlbum(name: "Saved", ids: ["one", "two"])
  store?.saveAnnotation(id: "one", title: "Title", description: "Body", date: nil, location: "Place")
  store = nil
  let restored = try LibraryStore(storeURL: url)
  XCTAssertEqual(restored.albums.first?.name, "Saved")
  XCTAssertEqual(restored.annotation(id: "one")?.descriptionText, "Body")
 }
 @MainActor func testPlaybackAndShuffle() throws {
  let suite = UUID().uuidString
  let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let playback = PlaybackController(defaults: defaults)
  let album = ContactAlbum(name: "Playback")
  playback.select(album: album, ids: ["a", "b", "c"], autoplay: false)
  playback.next(); XCTAssertEqual(playback.currentID, "b")
  playback.previous(); XCTAssertEqual(playback.currentID, "a")
  playback.shuffle = true
  var cycle = Set([try XCTUnwrap(playback.currentID)])
  playback.next(); cycle.insert(try XCTUnwrap(playback.currentID))
  playback.next(); cycle.insert(try XCTUnwrap(playback.currentID))
  XCTAssertEqual(cycle, Set(["a", "b", "c"]))
  playback.update(ids: [])
  XCTAssertNil(playback.currentID); XCTAssertFalse(playback.isPlaying)
  playback.resume(); XCTAssertFalse(playback.isPlaying)
 }
}
