import SwiftUI
import AppKit

// Uses the production views with an in-memory library and read-only sample photos.
@main struct AlbumShelfPreview: App {
    @StateObject private var store: LibraryStore
    @StateObject private var photos: PhotoRepository
    @State private var replay = 0
    @State private var sampleCount = 30

    init() {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STILL_PREVIEW_ROOT"]!)
        let library = try! LibraryStore(inMemory: true)
        let count = Int(ProcessInfo.processInfo.environment["STILL_PREVIEW_COUNT"] ?? "30") ?? 30
        Self.populate(library, count: count)
        _sampleCount = State(initialValue: count)
        _store = StateObject(wrappedValue: library)
        _photos = StateObject(wrappedValue: PhotoRepository(importsURL: root.appendingPathComponent("previews/photo-albums/assets"), observeLibrary: false))
    }

    var body: some Scene {
        Window("Still · CD 架预览", id: "shelf-preview") {
            LibraryView().environmentObject(store).environmentObject(photos)
                .id(replay)
                .frame(minWidth: 780, minHeight: 620)
                .toolbar {
                    ForEach([5, 30, 100], id: \.self) { count in
                        Button("\(count) 本") {
                            Self.populate(store, count: count)
                            sampleCount = count
                            replay += 1
                        }
                    }
                    Button("保存预览") { savePreview() }
                }
                .task(id: sampleCount) {
                    try? await Task.sleep(for: .seconds(2))
                    savePreview()
                }
        }.defaultSize(width: 1280, height: 860)
    }

    @MainActor private static func populate(_ library: LibraryStore, count: Int) {
        for album in library.albums { library.context.delete(album) }
        try! library.context.save()
        library.refresh()
        let names = ["山野之间", "海边的夏天", "远山来信", "一路向北", "周末散步", "日落以后",
                     "森林深处", "慢慢旅行", "留在秋天", "风吹过的地方", "城市漫游", "平凡的一天"]
        for index in 0..<count {
            let ids = (0..<(3 + index % 12)).map { "local:photo-\((index + $0) % 16).jpg" }
            let name = names[index % names.count] + (index < names.count ? "" : " · \(index / names.count + 1)")
            if let album = library.createAlbum(name: name, ids: ids) {
                album.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
                album.createdAt = Calendar.current.date(from: DateComponents(year: 2026 - index / 40, month: 11, day: 17 - index % 16))!
            }
        }
        try! library.context.save()
        library.refresh()
    }

    @MainActor private func savePreview() {
        guard let root = ProcessInfo.processInfo.environment["STILL_PREVIEW_ROOT"],
              let view = NSApp.windows.first(where: { $0.title.contains("CD 架预览") })?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let folder = URL(fileURLWithPath: root).appendingPathComponent("docs/cabinet-validation")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("cabinet-\(sampleCount).png")
        if let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: destination)
        }
    }
}
