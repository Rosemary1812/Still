import SwiftUI

@main
struct StillIOSApp: App {
    @StateObject private var library = MobileLibrary()

    private var previewColorScheme: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-still-dark") { return .dark }
        #endif
        return nil
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let store = library.store {
                    MobileAlbumShelf()
                        .environmentObject(store)
                        .environmentObject(library.photos)
                } else {
                    ContentUnavailableView("无法打开相册", systemImage: "externaldrive.badge.exclamationmark",
                                           description: Text(library.error ?? "请重新打开 Still。"))
                }
            }
            .tint(.primary)
            .preferredColorScheme(previewColorScheme)
        }
    }
}

@MainActor
final class MobileLibrary: ObservableObject {
    let photos: PhotoRepository
    @Published var store: LibraryStore?
    @Published var error: String?

    init() {
        var folder = "Still"
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let demo = arguments.contains("-still-demo")
        if demo { folder = "Still-Demo" }
        if let index = arguments.firstIndex(of: "-still-test-library"),
           arguments.indices.contains(index + 1), let id = UUID(uuidString: arguments[index + 1]) {
            folder = "Still-Tests/\(id.uuidString)"
        }
        #endif
        let root = URL.applicationSupportDirectory.appendingPathComponent(folder, isDirectory: true)
        photos = PhotoRepository(importsURL: root.appendingPathComponent("Imports"), observeLibrary: false)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = try LibraryStore(storeURL: root.appendingPathComponent("library.store"))
            self.store = store
            #if DEBUG
            if demo && store.albums.isEmpty { try seedDemo(store) }
            #endif
        } catch { self.error = error.localizedDescription }
    }

    #if DEBUG
    private func seedDemo(_ store: LibraryStore) throws {
        let names = ["山间来信", "在湖边", "森林漫游", "海风经过", "向山而行", "日落之前"]
        let files = [1, 0, 3, 6, 7, 8]
        let ids = try files.map { number in
            guard let url = Bundle.main.url(forResource: "photo-\(number)", withExtension: "jpg") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try photos.importData(Data(contentsOf: url))
        }
        for index in names.indices.reversed() {
            let ordered = Array(ids[index...] + ids[..<index])
            guard store.createAlbum(name: names[index], ids: ordered) != nil else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }
    #endif
}

struct MobilePhoto: View {
    let id: String?
    var fit = false
    var pixels: CGFloat = 800
    @EnvironmentObject private var photos: PhotoRepository
    @State private var image: UIImage?
    @State private var loaded = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.secondary.opacity(0.12)
                if let image {
                    Image(uiImage: image).resizable()
                        .aspectRatio(contentMode: fit ? .fit : .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else if loaded {
                    Image(systemName: "photo").font(.title).foregroundStyle(.secondary)
                } else { ProgressView() }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: "\(id ?? "")-\(pixels)") {
            image = nil
            loaded = false
            if let id { image = await photos.loadImage(id: id, size: CGSize(width: pixels, height: pixels)) }
            if !Task.isCancelled { loaded = true }
        }
        .accessibilityHidden(true)
    }
}
