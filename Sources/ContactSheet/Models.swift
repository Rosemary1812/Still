import Foundation
import SwiftData
import Combine

@Model final class ContactAlbum {
 @Attribute(.unique) var id: UUID
 var name: String
 var coverAssetID: String?
 var createdAt: Date
 var updatedAt: Date
 @Relationship(deleteRule: .cascade) var photos: [AlbumPhoto]
 init(name: String, photos: [AlbumPhoto] = []) { id = UUID(); self.name = name; self.photos = photos; createdAt = Date(); updatedAt = Date(); coverAssetID = photos.first?.assetIdentifier }
}
@Model final class AlbumPhoto {
 @Attribute(.unique) var id: UUID
 var assetIdentifier: String
 var sortIndex: Int
 init(assetIdentifier: String, sortIndex: Int) { id = UUID(); self.assetIdentifier = assetIdentifier; self.sortIndex = sortIndex }
}
@Model final class PhotoAnnotation {
 @Attribute(.unique) var assetIdentifier: String
 var title: String
 var descriptionText: String
 var displayDate: Date?
 var locationText: String
 var updatedAt: Date
 init(assetIdentifier: String, title: String = "", descriptionText: String = "", displayDate: Date? = nil, locationText: String = "") { self.assetIdentifier = assetIdentifier; self.title = title; self.descriptionText = descriptionText; self.displayDate = displayDate; self.locationText = locationText; updatedAt = Date() }
}
@MainActor final class LibraryStore: ObservableObject {
 let container: ModelContainer
 let context: ModelContext
 @Published var albums: [ContactAlbum] = []
 @Published var error: String?
 init(inMemory: Bool = false, storeURL: URL? = nil) throws {
  let schema = Schema([ContactAlbum.self, AlbumPhoto.self, PhotoAnnotation.self])
  let config: ModelConfiguration
  if let storeURL { config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none) }
  else { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none) }
  container = try ModelContainer(for: schema, configurations: [config]); context = ModelContext(container); context.autosaveEnabled = false; refresh()
 }
 func refresh() { do { albums = try context.fetch(FetchDescriptor<ContactAlbum>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])) } catch { self.error = error.localizedDescription } }
 @discardableResult private func save() -> Bool { do { try context.save(); error = nil; refresh(); objectWillChange.send(); return true } catch { self.error = error.localizedDescription; context.rollback(); refresh(); return false } }
 func orderedIDs(album: ContactAlbum) -> [String] { album.photos.sorted { $0.sortIndex < $1.sortIndex }.map(\.assetIdentifier) }
 func createAlbum(name: String, ids: [String]) -> ContactAlbum? { let name = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty, !ids.isEmpty else { error = "Choose photos and enter an album name."; return nil }; var seen = Set<String>(); let unique = ids.filter { seen.insert($0).inserted }; let album = ContactAlbum(name: name, photos: unique.enumerated().map { AlbumPhoto(assetIdentifier: $0.element, sortIndex: $0.offset) }); context.insert(album); return save() ? album : nil }
 func add(ids: [String], to album: ContactAlbum) { var seen = Set(orderedIDs(album: album)); for id in ids where seen.insert(id).inserted { album.photos.append(AlbumPhoto(assetIdentifier: id, sortIndex: album.photos.count)) }; if album.coverAssetID == nil { album.coverAssetID = album.photos.first?.assetIdentifier }; album.updatedAt = Date(); save() }
 func remove(ids: Set<String>, from album: ContactAlbum) { let removed = album.photos.filter { ids.contains($0.assetIdentifier) }; album.photos.removeAll { ids.contains($0.assetIdentifier) }; removed.forEach { context.delete($0) }; for (i,p) in album.photos.sorted(by: { $0.sortIndex < $1.sortIndex }).enumerated() { p.sortIndex = i }; if let cover = album.coverAssetID, ids.contains(cover) { album.coverAssetID = orderedIDs(album: album).first }; album.updatedAt = Date(); save() }
 func move(id: String, before: String, in album: ContactAlbum) { var ordered = album.photos.sorted { $0.sortIndex < $1.sortIndex }; guard id != before, let index = ordered.firstIndex(where: { $0.assetIdentifier == id }) else { return }; let photo = ordered.remove(at: index); guard let target = ordered.firstIndex(where: { $0.assetIdentifier == before }) else { return }; ordered.insert(photo, at: target); for (i,p) in ordered.enumerated() { p.sortIndex = i }; album.updatedAt = Date(); save() }
 func rename(album: ContactAlbum, name: String) { let name = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { error = "Album name cannot be empty."; return }; album.name = name; album.updatedAt = Date(); save() }
 func setCover(id: String, album: ContactAlbum) { guard orderedIDs(album: album).contains(id) else { return }; album.coverAssetID = id; save() }
 func delete(album: ContactAlbum) { context.delete(album); save() }
 func annotation(id: String) -> PhotoAnnotation? { do { var descriptor = FetchDescriptor<PhotoAnnotation>(predicate: #Predicate { $0.assetIdentifier == id }); descriptor.fetchLimit = 1; return try context.fetch(descriptor).first } catch { self.error = error.localizedDescription; return nil } }
 func saveAnnotation(id: String, title: String, description: String, date: Date?, location: String) { let value = annotation(id: id) ?? PhotoAnnotation(assetIdentifier: id); context.insert(value); value.title = title; value.descriptionText = description; value.displayDate = date; value.locationText = location; value.updatedAt = Date(); save() }
}
