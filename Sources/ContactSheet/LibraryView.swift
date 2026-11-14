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
                GeometryReader { geometry in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 38) {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("我的相册")
                                        .font(.system(size: 27, weight: .medium))
                                        .tracking(-0.8)
                                    Text("\(store.albums.count) 本相册 · 收藏生活里的片刻")
                                        .font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { importing = true } label: {
                                    Label("新建相册", systemImage: "plus")
                                        .font(.system(size: 12, weight: .medium))
                                        .padding(.horizontal, 16).padding(.vertical, 10)
                                        .background(Color.primary.opacity(0.055), in: Capsule())
                                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
                                }.buttonStyle(.plain)
                            }
                            if store.albums.isEmpty {
                                ContentUnavailableView { Label("创建第一本相册", systemImage: "rectangle.stack") }
                                description: { Text("从文件或 Apple 照片导入，留下照片与旁边的故事。") }
                                actions: { Button("导入照片，创建相册") { importing = true }.buttonStyle(.borderedProminent) }
                            } else {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 260), spacing: 32)], alignment: .leading, spacing: 36) {
                                    ForEach(store.albums) { album in
                                        AlbumShelfCard(album: album, coverID: album.coverAssetID ?? store.orderedIDs(album: album).first) {
                                            selected = album.id
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, geometry.size.width < 850 ? 36 : 52)
                        .padding(.top, 40).padding(.bottom, 52)
                        .frame(maxWidth: 1180, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .background(Color(nsColor: .underPageBackgroundColor).opacity(0.35))
                }

            }
        }
        .sheet(isPresented: $importing) { ImportView(existing: nil) { album in selected = album.id } }
        .alert("未能保存更改", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("好") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

private struct AlbumShelfCard: View {
    let album: ContactAlbum
    let coverID: String?
    let open: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    private var paper: Color { colorScheme == .dark ? Color(white: 0.22) : Color(red: 0.96, green: 0.95, blue: 0.92) }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(paper.opacity(0.8))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.08)))
                        .padding(.leading, 5).offset(x: 4, y: 4)
                    ZStack(alignment: .leading) {
                        paper
                        VStack(spacing: 0) {
                            AssetImage(id: coverID, fit: false)
                                .aspectRatio(1, contentMode: .fit)
                                .clipped()
                            HStack {
                                Text("PHOTO ALBUM").font(.system(size: 7, weight: .medium)).tracking(2)
                                Spacer()
                                Text(String(format: "%02d", album.photos.count)).font(.system(size: 9, design: .monospaced))
                            }.foregroundStyle(.secondary).padding(.top, 15)
                        }.padding(.leading, 23).padding(.trailing, 19).padding(.vertical, 21)
                        LinearGradient(colors: [.black.opacity(0.12), .white.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 12)
                        Rectangle().fill(.black.opacity(0.06)).frame(width: 1).padding(.leading, 12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.07)))
                }
                .shadow(color: .black.opacity(hovering ? 0.16 : 0.10), radius: hovering ? 14 : 8, x: 0, y: hovering ? 9 : 5)
                .offset(y: hovering && !reduceMotion ? -4 : 0)
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(album.name).font(.system(size: 15, weight: .medium)).lineLimit(2)
                        Text("\(album.photos.count) 张照片")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary).opacity(hovering ? 1 : 0).padding(.top, 3)
                }.padding(.horizontal, 3)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovering)
        .accessibilityLabel("\(album.name), \(album.photos.count) 张照片")
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
