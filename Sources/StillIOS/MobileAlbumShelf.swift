import SwiftUI

struct MobileAlbumShelf: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var selectedID: UUID?
    @State private var importing = false
    @State private var opened: ContactAlbum?
    @GestureState private var drag: CGFloat = 0

    private var index: Int { store.albums.firstIndex { $0.id == selectedID } ?? 0 }
    private var selected: ContactAlbum? { store.albums.isEmpty ? nil : store.albums[index] }
    private var visibleAlbums: [(depth: Int, index: Int, album: ContactAlbum)] {
        (0..<min(6, store.albums.count)).map { depth in
            let albumIndex = (index + depth) % store.albums.count
            return (depth, albumIndex, store.albums[albumIndex])
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: scheme == .dark ? 0.12 : 0.84).ignoresSafeArea()
                RadialGradient(colors: [.white.opacity(scheme == .dark ? 0.07 : 0.48), .clear],
                               center: .center, startRadius: 20, endRadius: 500).ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    if store.albums.isEmpty {
                        ContentUnavailableView {
                            Label("第一本相册，从这里开始", systemImage: "square.stack")
                        } description: {
                            Text("挑几张喜欢的照片，收成一本相册。")
                        } actions: {
                            Button("选择照片") { importing = true }.buttonStyle(.borderedProminent)
                        }
                    } else if typeSize.isAccessibilitySize || verticalSizeClass == .compact {
                        accessibleAlbums
                    } else {
                        stack
                        footer
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $opened) { album in MobileAlbumDetail(album: album) }
            .sheet(isPresented: $importing) {
                MobileImportSheet { album in selectedID = album.id }
            }
            .onChange(of: store.albums.map(\.id)) { _, ids in
                if let selectedID, !ids.contains(selectedID) { self.selectedID = ids.first }
            }
            .alert("未能保存", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("好", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }

    private var header: some View {
        HStack {
            Text("Still").font(.system(size: 29, weight: .semibold, design: .serif))
            Spacer()
            Button { importing = true } label: {
                Image(systemName: "plus").font(.system(size: 19, weight: .medium))
                    .frame(width: 48, height: 48).background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("新建相册").accessibilityIdentifier("newAlbum")
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
    }

    private var stack: some View {
        GeometryReader { geometry in
            let side = max(100, min(320, geometry.size.width - 88, geometry.size.height * 0.58))
            let step = min(35, max(16, (geometry.size.height - side - 48) / 6))
            let centerY = geometry.size.height / 2 + min(step * 1.7, 58)
            ZStack {
                ForEach(visibleAlbums, id: \.album.id) { entry in
                    let distance = entry.depth
                    Button {
                        if distance == 0 { opened = entry.album } else { select(entry.index) }
                    } label: {
                        MobileAlbumCover(album: entry.album, stacked: distance > 0)
                            .frame(width: side, height: side)
                    }
                    .buttonStyle(.plain)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : distance == 0 ? -5 : -13),
                                      axis: (x: 1, y: 0, z: 0), perspective: 0.3)
                    .rotationEffect(.degrees(reduceMotion ? 0 : distance == 0 ? -1.5 : Double(distance % 3) * 0.7))
                    .scaleEffect(1 - CGFloat(abs(distance)) * 0.018)
                    .shadow(color: .black.opacity(distance == 0 ? 0.23 : 0.16), radius: distance == 0 ? 18 : 3,
                            x: 0, y: distance == 0 ? 20 : 3)
                    .position(x: geometry.size.width / 2,
                              y: centerY - CGFloat(distance) * step + (reduceMotion ? 0 : drag * 0.13))
                    .zIndex(Double(10 - abs(distance)))
                    .accessibilityLabel("打开\(entry.album.name)")
                    .accessibilityHidden(distance != 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 20)
                .updating($drag) { value, state, _ in state = max(-100, min(100, value.translation.height)) }
                .onEnded { value in
                    let travel = value.predictedEndTranslation.height
                    if abs(travel) > 40 { select(index + (travel < 0 ? 1 : -1)) }
                })
            .accessibilityIdentifier("albumStack")
            .accessibilityAdjustableAction { direction in
                if direction == .increment { select(index + 1) }
                else if direction == .decrement { select(index - 1) }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 22) {
            HStack(spacing: 20) {
                Button { select(index - 1) } label: {
                    Image(systemName: "chevron.up").frame(width: 44, height: 44)
                }.disabled(index == 0).accessibilityLabel("上一本")
                Text("\(index + 1) / \(store.albums.count)")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("albumPosition")
                Button { select(index + 1) } label: {
                    Image(systemName: "chevron.down").frame(width: 44, height: 44)
                }.disabled(index == store.albums.count - 1).accessibilityLabel("下一本")
            }.buttonStyle(.plain)
            if let selected {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(selected.name).font(.title3.weight(.medium)).lineLimit(2)
                            .accessibilityIdentifier("selectedAlbumName")
                        Text("\(selected.photos.count) 张照片")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button { opened = selected } label: {
                        HStack(spacing: 8) {
                            Text("打开").font(.subheadline.weight(.medium))
                            Image(systemName: "arrow.up.right")
                        }
                        .padding(.horizontal, 22).frame(minHeight: 54)
                        .foregroundStyle(scheme == .dark ? .black : .white)
                        .background(scheme == .dark ? .white : .black, in: Capsule())
                    }.accessibilityIdentifier("openAlbum")
                }
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 20)
    }

    private var accessibleAlbums: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(store.albums) { album in
                    Button { opened = album } label: {
                        VStack(alignment: .leading) {
                            MobileAlbumCover(album: album).aspectRatio(1, contentMode: .fit).frame(maxWidth: 360)
                            Text(album.name).font(.headline)
                            Text("\(album.photos.count) 张照片").font(.body)
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(24)
        }
    }

    private func select(_ next: Int) {
        guard store.albums.indices.contains(next), next != index else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.84)) {
            selectedID = store.albums[next].id
        }
    }
}

struct MobileAlbumCover: View {
    let album: ContactAlbum
    var stacked = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                MobilePhoto(id: album.coverAssetID ?? album.photos.first?.assetIdentifier)
                LinearGradient(colors: [.black.opacity(0.5), .clear, .black.opacity(0.08)],
                               startPoint: .top, endPoint: .bottom)
                Text(album.name)
                    .font(.system(size: max(18, geometry.size.width * (stacked ? 0.067 : 0.085)), weight: .medium, design: .serif))
                    .lineLimit(stacked ? 1 : 2).minimumScaleFactor(0.75)
                    .foregroundStyle(.white).padding(.horizontal, 18).padding(.top, stacked ? 5 : 12)
                HStack(spacing: 0) {
                    Color.white.opacity(0.32).frame(width: 1)
                    LinearGradient(colors: [.black.opacity(0.3), .white.opacity(0.12), .clear],
                                   startPoint: .leading, endPoint: .trailing).frame(width: 7)
                    Spacer()
                }
            }
            .clipped().overlay(Rectangle().strokeBorder(.white.opacity(0.26), lineWidth: 0.75))
        }
    }
}
