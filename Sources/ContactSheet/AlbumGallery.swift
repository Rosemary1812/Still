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
    @State private var entranceStarted = false
    @State private var entranceFinished = false
    @AppStorage("albumGalleryPresentation") private var presentation = "covers"
    @AppStorage("albumCabinetSort") private var cabinetSort = "newest"
    @State private var search = ""
    @FocusState private var focused: UUID?
    @FocusState private var detailFocused: Bool
    private var detail: ContactAlbum? { store.albums.first { $0.id == inspecting } }
    private var ink: Color { scheme == .dark ? .white : Color(white: 0.12) }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if presentation == "spines" {
                    Color(white: scheme == .dark ? 0.12 : 0.975).ignoresSafeArea()
                } else { wall }
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
                        if presentation == "spines" {
                            spineShelves(size: geometry.size)
                        } else {
                            shelves(size: geometry.size)
                        }
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
            .task {
                guard !entranceStarted else { return }
                if reduceMotion || store.albums.isEmpty {
                    entranceStarted = true
                    entranceFinished = true
                    return
                }
                do {
                    // Give SwiftUI a rendered starting pose before scheduling the drop.
                    try await Task.sleep(for: .milliseconds(50))
                    entranceStarted = true
                    let lastIndex = min(9, max(0, store.albums.count - 1))
                    try await Task.sleep(for: .seconds(1.04 + Double(lastIndex) * 0.15))
                    entranceFinished = true
                } catch {
                    finishEntrance()
                }
            }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced {
                    finishEntrance()
                }
            }
        }
    }

    private func finishEntrance() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            entranceStarted = true
            entranceFinished = true
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
            Picker("相册展示方式", selection: $presentation) {
                Text("封面").tag("covers")
                Text("CD 架").tag("spines")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 132)
            .padding(.trailing, 16)
            .onChange(of: presentation) { _, _ in
                hovering = nil
                focused = nil
            }
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
                            ForEach(Array(store.albums.enumerated().dropFirst(row * columns).prefix(columns)), id: \.element.id) { index, album in
                                shelfAlbum(album, size: coverSize, index: index)
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

    private func spineShelves(size: CGSize) -> some View {
        let width = max(280, min(960, size.width - 80))
        let columns = AlbumCabinet.columns(width: width)
        let sections = AlbumCabinet.sections(store.albums, query: search, sort: cabinetSort)
        return ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索相册", text: $search).textFieldStyle(.plain)
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).accessibilityLabel("清除搜索")
                        }
                    }
                    .padding(9).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                    .frame(maxWidth: 250)
                    Spacer(minLength: 0)
                    Menu("跳转年份") {
                        ForEach(sections) { section in
                            Button("\(String(section.year)) · \(section.albums.count) 本") {
                                hovering = nil
                                focused = nil
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(section.year, anchor: .top)
                                }
                            }
                        }
                    }.fixedSize().disabled(sections.isEmpty)
                    Picker("排序", selection: $cabinetSort) {
                        Text("最新年份优先").tag("newest")
                        Text("最早年份优先").tag("oldest")
                        Text("年内按名称").tag("name")
                    }.labelsHidden().frame(width: 142)
                }
                .font(.system(size: 12))
                .frame(width: width)
                .padding(.top, 20)

                cabinetPreview.frame(width: width, height: 112)

                if sections.isEmpty {
                    ContentUnavailableView {
                        Label("没有找到相册", systemImage: "magnifyingglass")
                    } description: {
                        Text("试试其他名称，或清除搜索查看全部相册。")
                    } actions: {
                        Button("清除搜索") { search = "" }
                    }.frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sections) { section in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(String(section.year)).font(.system(size: 24, weight: .medium, design: .serif))
                                    Text("\(section.albums.count) 本相册").font(.system(size: 11)).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("按创建年份收藏").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                .padding(.top, 12).padding(.bottom, 14)
                                .id(section.year)
                                ForEach(0..<AlbumCabinet.rowCount(section.albums.count, columns: columns), id: \.self) { row in
                                    cabinetRow(Array(section.albums.dropFirst(row * columns).prefix(columns)), width: width)
                                        .id("\(section.year)-\(row)")
                                }
                                Color.clear.frame(height: 28)
                            }
                        }
                        .frame(width: width)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                    }
                    .id(search + "|" + cabinetSort)
                }
            }
            .onChange(of: search) { _, _ in
                hovering = nil; focused = nil
            }
            .onChange(of: cabinetSort) { _, _ in
                hovering = nil; focused = nil
            }
        }
    }

    private var cabinetPreview: some View {
        let album = store.albums.first { $0.id == (hovering ?? focused) }
        return HStack(spacing: 16) {
            if let album {
                AlbumSleeve(album: album).frame(width: 82, height: 82)
                    .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
                VStack(alignment: .leading, spacing: 7) {
                    Text(album.name).font(.system(size: 18, weight: .medium, design: .serif)).lineLimit(2)
                    Text("\(album.photos.count) 张照片 · \(album.createdAt.formatted(.dateTime.year().month().day()))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("相册收藏").font(.system(size: 23, weight: .medium, design: .serif))
                    Text("\(store.albums.count) 本相册 · 选中侧脊预览，点击翻阅")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
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

    private func shelfAlbum(_ album: ContactAlbum, size: CGFloat, index: Int) -> some View {
        let lifted = entranceFinished && (hovering == album.id || focused == album.id)
        let resting = reduceMotion || entranceStarted
        // Cap the stagger so large libraries do not wait for offscreen albums.
        let stagger = Double(min(index, 9)) * 0.075
        let dropDelay = 0.4 + stagger * 2
        return VStack(spacing: 0) {
            Button { inspect(album) } label: {
                Group {
                    if inspecting != album.id {
                        AlbumSleeve(album: album)
                            .matchedGeometryEffect(id: album.id, in: covers)
                            .rotation3DEffect(.degrees(reduceMotion || !resting || lifted ? 0 : 9), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.35)
                            .animation(reduceMotion ? nil : .timingCurve(0.5, 0, 0.75, 0, duration: 0.4).delay(dropDelay + 0.24), value: entranceStarted)
                            .rotationEffect(.degrees(reduceMotion || !lifted ? 0 : -1.5))
                            .shadow(color: .black.opacity(lifted || !resting ? 0.16 : 0.26), radius: lifted || !resting ? 15 : 5, x: 2, y: lifted || !resting ? 20 : 6)
                            .offset(y: reduceMotion ? 0 : lifted || !resting ? -22 : 0)
                            .animation(reduceMotion ? nil : .timingCurve(0.5, 0, 0.75, 0, duration: 0.4).delay(dropDelay), value: entranceStarted)
                            .opacity(resting ? 1 : 0)
                            .animation(reduceMotion ? nil : .linear(duration: 0.06).delay(0.4 + stagger), value: entranceStarted)
                    } else { Color.clear }
                }.frame(width: size, height: size)
            }
            .buttonStyle(.plain)
            .focused($focused, equals: album.id)
            .accessibilityLabel("\(album.name)，\(album.photos.count) 张照片，查看相册详情")
            .overlay(alignment: .bottom) {
                HStack(spacing: 8) {
                    Button { open(album) } label: {
                        shelfActionLabel("打开", size: size)
                    }
                    Button { inspect(album) } label: {
                        shelfActionLabel("详情", size: size)
                    }
                }
                .buttonStyle(.plain)
                .opacity(lifted && inspecting == nil ? 1 : 0)
                .allowsHitTesting(lifted && inspecting == nil)
                .accessibilityHidden(!lifted || inspecting != nil)
                .offset(y: 9)
            }
        }
        .disabled(!entranceFinished)
        .contentShape(Rectangle())
        .onHover { over in
            guard entranceFinished else { return }
            withAnimation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: over ? 1 : 0.4)) {
                hovering = over ? album.id : hovering == album.id ? nil : hovering
            }
        }
        .zIndex(lifted ? 1 : 0)
    }

    private func shelfActionLabel(_ title: String, size: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .frame(width: min(90, size * 0.38), height: 34)
            .background(scheme == .dark ? Color(white: 0.26).opacity(0.95) : Color(white: 0.97).opacity(0.92), in: Capsule())
            .contentShape(Capsule())
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

private struct AlbumSpine: View {
    let album: ContactAlbum
    let index: Int
    let height: CGFloat
    @EnvironmentObject private var store: LibraryStore
    private var width: CGFloat { height * 0.105 }
    private var darkPrint: Bool { index % 6 == 2 || index % 6 == 4 }
    private var ink: Color { darkPrint ? Color(white: 0.94) : Color(white: 0.1) }
    private var paper: Color {
        let colors: [Color] = [Color(red: 0.91, green: 0.87, blue: 0.77),
                               Color(red: 0.78, green: 0.33, blue: 0.20),
                               Color(red: 0.08, green: 0.17, blue: 0.25),
                               Color(red: 0.23, green: 0.59, blue: 0.73),
                               Color(red: 0.12, green: 0.19, blue: 0.16),
                               Color(red: 0.95, green: 0.71, blue: 0.25)]
        return colors[index % colors.count]
    }

    var body: some View {
        ZStack {
            Color(white: 0.24)
            ZStack {
                paper
                AssetImage(id: album.coverAssetID ?? store.orderedIDs(album: album).first, fit: false)
                    .opacity(darkPrint ? 0.55 : 0.38)
                paper.opacity(0.4)
                VStack {
                    Spacer()
                    AssetImage(id: album.coverAssetID ?? store.orderedIDs(album: album).first, fit: false)
                        .frame(height: height * 0.29)
                        .mask(SpinePaperCut())
                }
                VStack(spacing: 0) {
                    Image(systemName: index % 2 == 0 ? "camera.aperture" : "sun.max.fill")
                        .font(.system(size: width * 0.48, weight: .medium))
                        .padding(.top, 14)
                    Spacer()
                    Text("STILL")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(paper)
                    Text(album.createdAt.formatted(.dateTime.year()))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity)
                        .background(paper)
                }
                Text(album.name)
                    .font(.system(size: width * 0.66, weight: index % 3 == 0 ? .semibold : .black, design: index % 3 == 0 ? .serif : .default))
                    .tracking(index % 3 == 0 ? 3 : 1)
                    .lineLimit(1).minimumScaleFactor(0.55)
                    .frame(width: height * 0.58, alignment: .leading)
                    .rotationEffect(.degrees(90))
            }
            .foregroundStyle(ink)
            .frame(width: width - 9, height: height - 35)
            .clipped()
            JewelCaseSurface(seed: index)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .accessibilityElement(children: .ignore)
    }
}

private struct SpinePaperCut: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: rect.height * 0.16))
            for i in 0...12 {
                p.addLine(to: CGPoint(x: rect.width * CGFloat(i) / 12,
                                     y: rect.height * (0.16 + CGFloat((i * 7) % 5) * 0.012) + rect.width * CGFloat(i) / 18))
            }
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: 0, y: rect.maxY))
            p.closeSubpath()
        }
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
    struct YearSection: Identifiable {
        let year: Int
        let albums: [ContactAlbum]
        var id: Int { year }
    }

    static func columns(width: CGFloat) -> Int {
        max(1, min(18, Int((width - 64 + 8) / (320 * 0.105 + 8))))
    }

    static func rowCount(_ count: Int, columns: Int) -> Int {
        (count + columns - 1) / columns
    }

    static func appearanceIndex(_ id: UUID) -> Int {
        id.uuidString.utf8.reduce(0) { ($0 * 31 + Int($1)) % 997 }
    }

    static func sections(_ albums: [ContactAlbum], query: String, sort: String) -> [YearSection] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = albums.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
        let grouped = Dictionary(grouping: filtered) { Calendar.current.component(.year, from: $0.createdAt) }
        let years = grouped.keys.sorted { sort == "oldest" ? $0 < $1 : $0 > $1 }
        return years.map { year in
            let ordered = grouped[year, default: []].sorted { a, b in
                if sort == "name", a.name != b.name {
                    return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
                if a.createdAt == b.createdAt { return a.id.uuidString < b.id.uuidString }
                return sort == "oldest" ? a.createdAt < b.createdAt : a.createdAt > b.createdAt
            }
            return YearSection(year: year, albums: ordered)
        }
    }
}
