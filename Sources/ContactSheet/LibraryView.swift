import SwiftUI
import AppKit

struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var selected: UUID?
    @State private var importing = false
    var body: some View {
        Group {
            if let album = store.albums.first(where: { $0.id == selected }) {
                AlbumExperience(album: album) { selected = nil }.id(album.id)
            } else {
                AlbumGallery(importing: $importing) { selected = $0.id }

            }
        }
        .sheet(isPresented: $importing) { ImportView(existing: nil) { album in selected = album.id } }
        .alert("未能保存更改", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("好") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct PhotoEditTarget: Identifiable { let id: String }
extension String { var nonEmpty: String? { trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? nil : self } }

struct AssetImage: View {
    let id: String?
    var fit = true
    @EnvironmentObject var photos: PhotoRepository
    @State private var image: NSImage?
    @State private var loading = false
    @State private var retry = 0
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.primary.opacity(0.035)
                if let image {
                    Image(nsImage:image).resizable().aspectRatio(contentMode:fit ? .fit : .fill).frame(width:geo.size.width,height:geo.size.height).clipped()
                } else if loading { ProgressView().controlSize(.small) }
                else if id != nil {
                    VStack(spacing:6) { Image(systemName:"photo.badge.exclamationmark"); Text("Photo unavailable").font(.caption2); Button("Retry") { retry += 1 }.font(.caption2) }.foregroundStyle(.secondary)
                } else { Image(systemName:"photo").foregroundStyle(.tertiary) }
            }
            .task(id:"\(id ?? "")-\(photos.revision)-\(retry)-\(Int(ceil(geo.size.width / 128)))-\(Int(ceil(geo.size.height / 128)))") {
                guard let id else { image = nil; return }; image = nil; loading = true
                let result = await photos.loadImage(id:id,size:CGSize(width:max(geo.size.width,320)*2,height:max(geo.size.height,320)*2))
                guard !Task.isCancelled else { return }; image = result; loading = false
            }
        }
    }
}
