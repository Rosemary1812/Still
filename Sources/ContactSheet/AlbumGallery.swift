import SwiftUI

struct AlbumGallery: View {
    @Binding var importing: Bool
    let open: (ContactAlbum) -> Void
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Namespace private var covers
    @State private var inspecting: UUID?
    @State private var hovering: UUID?
    @FocusState private var focused: UUID?
    @FocusState private var detailFocused: Bool
    private var detail: ContactAlbum? { store.albums.first { $0.id == inspecting } }
    private var ink: Color { scheme == .dark ? .white : Color(white: 0.12) }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                wall
                VStack(spacing: 0) {
                    header.padding(.horizontal, 30).padding(.top, 24)
                    if store.albums.isEmpty {
                        ContentUnavailableView {
                            Label("创建第一本相册", systemImage: "square.stack")
                        } description: {
                            Text("从文件或 Apple 照片导入，留下照片与旁边的故事。")
                        } actions: {
                            Button("导入照片，创建相册") { importing = true }
                        }.frame(maxHeight: .infinity)
                    } else {
                        shelves(size: geometry.size)
                    }
                }
                .blur(radius: detail == nil ? 0 : 5)
                .opacity(detail == nil ? 1 : 0.24)
                .allowsHitTesting(detail == nil)
                .accessibilityHidden(detail != nil)

                if let album = detail {
                    Color.black.opacity(scheme == .dark ? 0.18 : 0.035)
                        .contentShape(Rectangle()).onTapGesture { dismiss() }
                    detailView(album, size: geometry.size).zIndex(2)
                }
            }
            .foregroundStyle(ink)
            .onExitCommand { dismiss() }
            .onChange(of: store.albums.map(\.id)) { _, ids in
                if let inspecting, !ids.contains(inspecting) { dismiss() }
            }
        }
    }

    private var wall: some View {
        ZStack {
            Color(white: scheme == .dark ? 0.16 : 0.83)
            RadialGradient(colors: [Color.white.opacity(scheme == .dark ? 0.09 : 0.75), .clear],
                           center: UnitPoint(x: 0.52, y: 0.40), startRadius: 20, endRadius: 650)
            LinearGradient(colors: [.black.opacity(0.025), .clear, .black.opacity(0.045)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }.ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Still").font(.system(size: 23, weight: .semibold, design: .serif))
            Spacer()
            Button { importing = true } label: {
                Label("新建相册", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .foregroundStyle(scheme == .dark ? .black : .white)
                    .background(ink, in: Capsule())
            }.buttonStyle(.plain).opacity(detail == nil ? 1 : 0)
        }
    }

    private func shelves(size: CGSize) -> some View {
        let width = min(1100, size.width - 100)
        let columns = max(1, min(store.albums.count, min(5, Int(width / 185))))
        let rows = (store.albums.count + columns - 1) / columns
        let coverSize = min(240, (width - 64 - CGFloat(columns - 1) * 26) / CGFloat(columns))
        let rowHeight = coverSize + 78
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    ZStack(alignment: .bottom) {
                        ShelfLedge().frame(height: 17).offset(y: 5)
                        HStack(alignment: .bottom, spacing: 26) {
                            ForEach(Array(store.albums.dropFirst(row * columns).prefix(columns))) { album in
                                shelfAlbum(album, size: coverSize)
                            }
                        }.padding(.bottom, 8)
                    }
                    .frame(width: width, height: rowHeight, alignment: .bottom)
                    .padding(.bottom, 44)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, max(28, (size.height - 110 - CGFloat(rows) * (rowHeight + 44)) / 2))
            .padding(.bottom, 45)
        }.scrollIndicators(.hidden)
    }

    private func shelfAlbum(_ album: ContactAlbum, size: CGFloat) -> some View {
        let lifted = hovering == album.id || focused == album.id
        return VStack(spacing: 0) {
            Button { inspect(album) } label: {
                Group {
                    if inspecting != album.id {
                        AlbumSleeve(album: album)
                            .matchedGeometryEffect(id: album.id, in: covers)
                            .rotation3DEffect(.degrees(reduceMotion ? 0 : lifted ? 0 : 9), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
                            .rotationEffect(.degrees(reduceMotion || !lifted ? 0 : -1.5))
                            .shadow(color: .black.opacity(lifted ? 0.22 : 0.26), radius: lifted ? 15 : 5, x: 2, y: lifted ? 20 : 6)
                            .offset(y: reduceMotion || !lifted ? 0 : -22)
                    } else { Color.clear }
                }.frame(width: size, height: size)
            }
            .buttonStyle(.plain)
            .focused($focused, equals: album.id)
            .accessibilityLabel("\(album.name)，\(album.photos.count) 张照片，查看相册详情")
            .overlay(alignment: .bottom) {
                HStack(spacing: 6) {
                    Button("打开") { open(album) }
                    Button("详情") { inspect(album) }
                }
                .font(.system(size: 10, weight: .medium)).buttonStyle(.plain)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .opacity(lifted && inspecting == nil ? 1 : 0)
                .allowsHitTesting(lifted && inspecting == nil)
                .accessibilityHidden(!lifted || inspecting != nil)
                .offset(y: 9)
            }
        }
        .contentShape(Rectangle())
        .onHover { over in
            withAnimation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: over ? 1 : 0.4)) {
                hovering = over ? album.id : hovering == album.id ? nil : hovering
            }
        }
        .zIndex(lifted ? 1 : 0)
    }

    private func detailView(_ album: ContactAlbum, size: CGSize) -> some View {
        let side = min(430, size.height * 0.51, size.width * 0.44)
        return ZStack(alignment: .topTrailing) {
            ZStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text(album.name).font(.system(size: size.width < 900 ? 24 : 30, weight: .medium, design: .serif))
                    Text("\(album.photos.count) 张照片")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Text("创建于 \(album.createdAt.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)

                }.frame(width: min(230, size.width * 0.24), alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 30)
                VStack(spacing: 24) {
                    AlbumSleeve(album: album)
                    .matchedGeometryEffect(id: album.id, in: covers)
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 24)
                    Button { open(album) } label: {
                        Label("打开相册", systemImage: "arrow.up.right")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 24).padding(.vertical, 13)
                            .foregroundStyle(scheme == .dark ? .black : .white).background(ink, in: Capsule())
                    }.buttonStyle(.plain).keyboardShortcut(.return, modifiers: [])
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(action: dismiss) { Label("放回", systemImage: "xmark").font(.system(size: 12)).padding(12).background(.regularMaterial, in: Capsule()) }
                .buttonStyle(.plain).padding(28)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($detailFocused)
        .onAppear { detailFocused = true }
    }

    private func inspect(_ album: ContactAlbum) {
        withAnimation(reduceMotion ? nil : .timingCurve(0.65, 0, 0.25, 1, duration: 0.7)) { inspecting = album.id; hovering = nil }
    }
    private func dismiss() {
        let previous = inspecting
        withAnimation(reduceMotion ? nil : .timingCurve(0.65, 0, 0.25, 1, duration: 0.7)) { inspecting = nil }
        focused = previous
    }
}

private struct AlbumSleeve: View {
    let album: ContactAlbum
    @EnvironmentObject private var store: LibraryStore
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                AssetImage(id: album.coverAssetID ?? store.orderedIDs(album: album).first, fit: false)
                LinearGradient(stops: [.init(color: .clear, location: 0.36), .init(color: .black.opacity(0.65), location: 1)], startPoint: .top, endPoint: .bottom)
                Text(album.name)
                    .font(.system(size: max(16, geometry.size.width * 0.085), weight: .medium, design: .serif))
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .padding(geometry.size.width * 0.075).foregroundStyle(.white)
                LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 6)
            }
            .clipped()
            .overlay(Rectangle().strokeBorder(.white.opacity(0.22), lineWidth: 0.75))
        }
    }
}

private struct ShelfLedge: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 0) {
            ShelfTop().fill(LinearGradient(colors: [Color(white: scheme == .dark ? 0.36 : 0.94), Color(white: scheme == .dark ? 0.48 : 1)], startPoint: .top, endPoint: .bottom)).frame(height: 11)
            Rectangle().fill(LinearGradient(colors: [Color(white: scheme == .dark ? 0.4 : 0.98), Color(white: scheme == .dark ? 0.25 : 0.79)], startPoint: .top, endPoint: .bottom)).frame(height: 6)
        }
        .shadow(color: .black.opacity(0.28), radius: 15, x: 0, y: 24)
        .shadow(color: .black.opacity(0.13), radius: 3, x: 0, y: 6)
    }
}

private struct ShelfTop: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 18, y: 0)); p.addLine(to: CGPoint(x: rect.maxX - 18, y: 0))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: 0, y: rect.maxY)); p.closeSubpath()
        }
    }
}
