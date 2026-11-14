import SwiftUI
import AppKit

// Uses the production views with an in-memory library and read-only sample photos.
@main struct AlbumShelfPreview: App {
    @StateObject private var store: LibraryStore
    @StateObject private var photos: PhotoRepository

    init() {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STILL_PREVIEW_ROOT"]!)
        let library = try! LibraryStore(inMemory: true)
        let names = ["山野之间", "海边的夏天", "远山来信", "一路向北", "周末散步", "日落以后",
                     "森林深处", "慢慢旅行", "留在秋天", "风吹过的地方", "城市漫游", "平凡的一天"]
        for index in names.indices.reversed() {
            let ids = (0..<(3 + index)).map { "local:photo-\((index + $0) % 16).jpg" }
            _ = library.createAlbum(name: names[index], ids: ids)
        }
        _store = StateObject(wrappedValue: library)
        _photos = StateObject(wrappedValue: PhotoRepository(importsURL: root.appendingPathComponent("previews/photo-albums/assets"), observeLibrary: false))
    }

    var body: some Scene {
        Window("Still · 12 本示例相册", id: "shelf-preview") {
            LibraryView().environmentObject(store).environmentObject(photos)
                .frame(minWidth: 780, minHeight: 620)
                .task {
                    try? await Task.sleep(for: .seconds(2))
                    savePreview()
                }
        }.defaultSize(width: 1280, height: 860)
    }

    @MainActor private func savePreview() {
        guard let root = ProcessInfo.processInfo.environment["STILL_PREVIEW_ROOT"],
              let view = NSApp.windows.first(where: { $0.title.contains("12 本") })?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let destination = URL(fileURLWithPath: root).appendingPathComponent("docs/editions-album-validation/title-only-many-albums.png")
        if let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: destination)
        }
    }
}
