import SwiftUI

struct AlbumGallery: View {
    @Binding var importing: Bool
    let open: (ContactAlbum) -> Void
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var inspecting: UUID?
    @State private var hovering: UUID?
    @FocusState private var focused: UUID?
    @FocusState private var detailFocused: Bool
    private var detail: ContactAlbum? { store.albums.first { $0.id == inspecting } }
    private var ink: Color { scheme == .dark ? .white : Color(white: 0.12) }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(white: scheme == .dark ? 0.12 : 0.975).ignoresSafeArea()
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
                        spineShelves(size: geometry.size)
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

    private func spineShelves(size: CGSize) -> some View {
        let width = max(280, min(960, size.width - 80))
        let columns = AlbumCabinet.columns(width: width)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<AlbumCabinet.rowCount(store.albums.count, columns: columns), id: \.self) { row in
                    cabinetRow(Array(store.albums.dropFirst(row * columns).prefix(columns)), width: width)
                }
            }
            .frame(width: width)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func cabinetRow(_ albums: [ContactAlbum], width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(Color(white: scheme == .dark ? 0.19 : 0.88))
            LinearGradient(colors: [.black.opacity(0.17), .clear, .white.opacity(0.12)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(albums) { album in
                    spineAlbum(album, index: AlbumCabinet.appearanceIndex(album.id), height: 320)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 14)
            HStack {
                cabinetSide
                Spacer()
                cabinetSide
            }
            ShelfLedge().frame(height: 17).offset(y: 2)
        }
        .frame(width: width, height: 374)
        .overlay(alignment: .top) {
            Rectangle().fill(Color(white: scheme == .dark ? 0.32 : 0.97)).frame(height: 8)
                .shadow(color: .black.opacity(0.15), radius: 3, y: 3)
        }
    }

    private var cabinetSide: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Color(white: scheme == .dark ? 0.34 : 0.99), Color(white: scheme == .dark ? 0.24 : 0.81)], startPoint: .leading, endPoint: .trailing))
            .frame(width: 12)
            .shadow(color: .black.opacity(0.18), radius: 4, x: 3)
    }

    private func spineAlbum(_ album: ContactAlbum, index: Int, height: CGFloat) -> some View {
        let lifted = hovering == album.id || focused == album.id
        return Button { inspect(album) } label: {
            AlbumSpine(album: album, index: index, height: height)
                .opacity(inspecting == album.id ? 0 : 1)
                .shadow(color: .black.opacity(lifted ? 0.25 : 0.1), radius: lifted ? 8 : 1, x: lifted ? 3 : 1, y: lifted ? 10 : 2)
                .offset(y: lifted && !reduceMotion ? -18 : 0)
                .padding(.top, 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused, equals: album.id)
        .onHover { over in
            hovering = over ? album.id : hovering == album.id ? nil : hovering
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: lifted)
        .accessibilityLabel("\(album.name)，\(album.photos.count) 张照片，查看相册详情")
        .help(album.name)
        .onDisappear {
            if hovering == album.id { hovering = nil }
        }
        .contextMenu {
            Button("打开相册") { open(album) }
            Button("查看详情") { inspect(album) }
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

private struct AlbumSpine: View {
    let album: ContactAlbum
    let index: Int
    let height: CGFloat
    @EnvironmentObject private var store: LibraryStore
    private var width: CGFloat { height * 0.105 }

    var body: some View {
        ZStack {
            Color(white: 0.24)
            AssetImage(id: album.coverAssetID ?? store.orderedIDs(album: album).first, fit: false)
                .frame(width: width - 9, height: height - 35)
                .clipped()
            JewelCaseSurface(seed: index)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .accessibilityElement(children: .ignore)
    }
}

private struct JewelCaseSurface: View {
    let seed: Int
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let outer = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            context.stroke(Path(roundedRect: outer, cornerRadius: 2), with: .color(.black.opacity(0.8)), lineWidth: 1)
            for (x, opacity, thickness) in [(1.5, 0.85, 1.0), (3.0, 0.4, 1.0), (w - 4, 0.65, 1.0), (w - 1.5, 0.9, 1.0)] {
                let strip = CGRect(x: x, y: 2, width: thickness, height: h - 4)
                context.fill(Path(strip), with: .linearGradient(Gradient(colors: [.white.opacity(opacity), .gray.opacity(0.2), .white.opacity(opacity), .black.opacity(0.6)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            }
            for y in [CGFloat(2), h - 16] {
                let cap = CGRect(x: 3, y: y, width: w - 6, height: 14)
                context.fill(Path(roundedRect: cap, cornerRadius: 2), with: .linearGradient(Gradient(colors: [Color(white: 0.12), Color(white: 0.62), Color(white: 0.22), Color(white: 0.07), Color(white: 0.55)]), startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: 0, y: y + 14)))
                context.stroke(Path(roundedRect: cap.insetBy(dx: 2, dy: 2), cornerRadius: 2), with: .color(.white.opacity(0.5)), lineWidth: 0.6)
                for x in stride(from: CGFloat(7), to: w - 5, by: 4) {
                    context.stroke(Path(CGRect(x: x, y: y + 1, width: 1, height: 12)), with: .color(.white.opacity(0.2)), lineWidth: 0.5)
                }
            }
            // Deterministic grain and hairline scuffs stay fixed while hovering.
            var state = UInt64(seed + 1) * 7919
            func random() -> CGFloat {
                state = state &* 6364136223846793005 &+ 1
                return CGFloat((state >> 33) % 10000) / 10000
            }
            for _ in 0..<700 {
                let x = random() * w, y = random() * h
                let alpha = random() * 0.13
                context.fill(Path(CGRect(x: x, y: y, width: 0.6, height: 0.6)), with: .color(.white.opacity(alpha)))
            }
            for _ in 0..<24 {
                let x = random() * w, y = random() * h
                var scratch = Path()
                scratch.move(to: CGPoint(x: x, y: y))
                scratch.addLine(to: CGPoint(x: min(w - 3, x + random() * 12), y: min(h - 3, y + random() * 30)))
                context.stroke(scratch, with: .color(.white.opacity(0.09)), lineWidth: 0.45)
            }
        }
        .allowsHitTesting(false)
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

struct AlbumCabinet {
    static func columns(width: CGFloat) -> Int {
        max(1, min(18, Int((width - 64 + 8) / (320 * 0.105 + 8))))
    }

    static func rowCount(_ count: Int, columns: Int) -> Int {
        (count + columns - 1) / columns
    }

    static func appearanceIndex(_ id: UUID) -> Int {
        id.uuidString.utf8.reduce(0) { ($0 * 31 + Int($1)) % 997 }
    }

}
