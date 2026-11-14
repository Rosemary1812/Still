import SwiftUI

// Coordinates measured from the 1814 × 1518 Mac Sleeve window.
struct AlbumWallLayout {
    static let secondsPerTile = 379.5 / (171.0 / 7.739)
    static let offsets = [151.0, 296.0, 62.0, 207.0].map { $0 / 379.5 - 1 }
    static func indices(count: Int, row: Int) -> [Int] {
        guard count > 0 else { return [] }
        let values = Array(stride(from: row, to: count, by: 4))
        return values.isEmpty ? [row % count] : values
    }
    static func phase(_ value: Double, period: Int) -> Double {
        guard period > 0 else { return 0 }
        let p = Double(period)
        return (value.truncatingRemainder(dividingBy: p) + p).truncatingRemainder(dividingBy: p)
    }
}

private enum AlbumReadingMode: String, CaseIterable { case preview = "预览", book = "双页相册" }

struct AlbumExperience: View {
    let album: ContactAlbum
    let back: () -> Void
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var photos: PhotoRepository
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: String?
    @State private var mode = AlbumReadingMode.preview
    @State private var adding = false
    @State private var editing: PhotoEditTarget?
    @State private var paused = false
    @State private var phase = 0.0
    @State private var started: Date?
    @State private var dragging = false
    @State private var controls = true
    @State private var hideControls: Task<Void, Never>?
    @State private var renaming = false
    @State private var name = ""
    @State private var deleting = false
    @State private var removing = false
    var ids: [String] { store.orderedIDs(album: album) }
    var showingWall: Bool { selected == nil && mode == .preview }
    var selectedIndex: Int { selected.flatMap { ids.firstIndex(of: $0) } ?? 0 }
    private let paper = Color(nsColor: .windowBackgroundColor)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                if ids.isEmpty {
                    ContentUnavailableView { Label("相册里还没有照片", systemImage: "photo.on.rectangle") }
                    description: { Text("导入照片后，即可浏览照片墙和双页相册。") }
                    actions: { Button("导入照片") { adding = true }.buttonStyle(.borderedProminent) }
                } else if showingWall {
                    wall(size: geometry.size)
                } else if let id = selected ?? ids.first {
                    reader(id: id)
                        .padding(.top, 62)
                }
                toolbar
                    .padding(.horizontal, 18).padding(.top, 12)
                    .opacity(!showingWall || controls ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: controls)
            }
            .background(paper)
            .onContinuousHover { state in
                if case .active = state { wakeControls() }
            }
        }
        .onAppear { paused = reduceMotion; resumeMotion(); wakeControls() }
        .onDisappear { freezeMotion(); hideControls?.cancel() }
        .onChange(of: showingWall) { _, wall in wall ? resumeMotion() : freezeMotion(); wakeControls() }
        .onChange(of: paused) { _, value in value ? freezeMotion() : resumeMotion() }
        .onChange(of: reduceMotion) { _, value in paused = value }
        .onChange(of: ids) { _, values in if let selected, !values.contains(selected) { self.selected = values.first }; if values.isEmpty { mode = .preview } }
        .sheet(isPresented: $adding) { ImportView(existing: album) { _ in } }
        .sheet(item: $editing) { target in AnnotationEditor(id: target.id) }
        .alert("重命名相册", isPresented: $renaming) {
            TextField("相册名称", text: $name)
            Button("取消", role: .cancel) {}
            Button("保存") { store.rename(album: album, name: name) }
        }
        .confirmationDialog("删除这本相册？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除相册", role: .destructive) { store.delete(album: album); if store.error == nil { back() } }
        } message: { Text("只删除相册，不删除原始照片和已保存的照片描述。") }
        .confirmationDialog("从这本相册中移除照片？", isPresented: $removing, titleVisibility: .visible) {
            Button("移除照片", role: .destructive) { if let selected { store.remove(ids: [selected], from: album) } }
        } message: { Text("照片副本和描述仍会保留。") }
        .onKeyPress { _ in controls = true; hideControls?.cancel(); return .ignored }
        .onExitCommand { if showingWall { back() } else { selected = nil; mode = .preview } }
        .onMoveCommand { direction in
            guard !showingWall, editing == nil else { return }
            if direction == .left { step(-1) }; if direction == .right { step(1) }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button(action: back) { Label("全部相册", systemImage: "chevron.left") }
            Spacer(minLength: 12)
            Picker("阅读方式", selection: $mode) {
                ForEach(AlbumReadingMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 180)
                .onChange(of: mode) { _, value in
                    if value == .book && selected == nil { selected = ids.first }
                    if value == .preview { selected = nil }
                }
            Spacer(minLength: 12)
            if showingWall && !ids.isEmpty {
                Button { paused.toggle() } label: { Image(systemName: paused ? "play.fill" : "pause.fill") }
                    .help(paused ? "继续流动" : "暂停流动")
                    .accessibilityLabel(paused ? "继续流动" : "暂停流动")
            }
            Button { adding = true } label: { Label("导入照片", systemImage: "plus") }
            Menu {
                Button("重命名相册") { name = album.name; renaming = true }
                Button("删除相册", role: .destructive) { deleting = true }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
    }

    private func wall(size: CGSize) -> some View {
        let tile = max(1, size.height / 4)
        let columns = Int(ceil(size.width / tile)) + 2
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: started == nil)) { timeline in
            let progress = phase - dragTranslation + (started.map { timeline.date.timeIntervalSince($0) / AlbumWallLayout.secondsPerTile } ?? 0)
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { row in
                    let members = AlbumWallLayout.indices(count: ids.count, row: row)
                    let displacement = AlbumWallLayout.phase(progress - AlbumWallLayout.offsets[row], period: members.count)
                    let first = Int(floor(displacement))
                    HStack(spacing: 0) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = members[(first + column) % members.count]
                            let id = ids[index]
                            Button { if !dragging { selected = id; freezeMotion() } } label: {
                                AssetImage(id: id, fit: false).frame(width: tile, height: tile).clipped()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("查看第 \(index + 1) 张照片与描述")
                        }
                    }
                    .offset(x: -(displacement - floor(displacement)) * tile)
                    .frame(width: size.width, height: tile, alignment: .leading)
                    .clipped()
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .simultaneousGesture(DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !dragging { freezeMotion(); dragging = true }
                dragTranslation = value.translation.width / tile
            }
            .onEnded { value in
                phase -= value.translation.width / tile
                dragTranslation = 0
                dragging = false
                resumeMotion()
            })
        .overlay(alignment: .bottomLeading) {
            if controls { Text(album.name + " · \(ids.count) 张").font(.caption).padding(10).background(.regularMaterial, in: Capsule()).padding(16).allowsHitTesting(false) }
        }
    }
    @State private var dragTranslation = 0.0

    private func reader(id: String) -> some View {
        let annotation = store.annotation(id: id)
        let title = annotation?.title.nonEmpty ?? "第 \(selectedIndex + 1) 个片刻"
        return VStack(spacing: 0) {
            HStack {
                Button("‹ 照片预览") { selected = nil; mode = .preview }
                Spacer()
                Text("\(album.name) · \(selectedIndex + 1) / \(ids.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if mode == .preview { Button("用双页相册阅读 →") { mode = .book } }
            }.padding(.horizontal, 28).padding(.vertical, 14)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    AssetImage(id: id, fit: true)
                        .padding(30)
                        .frame(width: geometry.size.width * 0.60)
                    if mode == .book {
                        LinearGradient(colors: [.black.opacity(0), .black.opacity(0.10), .black.opacity(0)], startPoint: .leading, endPoint: .trailing).frame(width: 12)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("\(selectedIndex + 1, format: .number.precision(.integerLength(2))) / \(ids.count)").font(.caption).foregroundStyle(.secondary)
                            Text(title).font(.system(size: 26, weight: .regular, design: .serif)).textSelection(.enabled)
                            if let date = annotation?.displayDate { Text(date, style: .date).font(.caption).foregroundStyle(.secondary) }
                            if let location = annotation?.locationText.nonEmpty { Text(location).font(.caption).foregroundStyle(.secondary) }
                            Text(annotation?.descriptionText.nonEmpty ?? "为这张照片写下第一段回忆。")
                                .font(.system(size: 16, design: .serif)).lineSpacing(8).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack {
                                Button("编辑描述") { editing = PhotoEditTarget(id: id) }
                                Menu {
                                    Button("设为相册封面") { store.setCover(id: id, album: album) }
                                    Button("从相册移除", role: .destructive) { removing = true }
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
                            }
                        }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(paper)
                .shadow(color: .black.opacity(mode == .book ? 0.08 : 0), radius: 15, y: 6)
            }.padding(.horizontal, mode == .book ? 28 : 0).padding(.vertical, 12)
            if mode == .preview {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(ids.enumerated()), id: \.element) { index, photoID in
                            Button { selected = photoID } label: {
                                AssetImage(id: photoID, fit: false).frame(width: 54, height: 54).clipped()
                                    .overlay { Rectangle().stroke(photoID == id ? Color.accentColor : .clear, lineWidth: 2) }
                            }.buttonStyle(.plain).accessibilityLabel("第 \(index + 1) 张")
                        }
                    }.padding(.horizontal, 28).padding(.vertical, 10)
                }.frame(height: 76)
            }
            HStack {
                Button(mode == .book ? "← 上一页" : "← 上一张") { step(-1) }.disabled(selectedIndex == 0)
                Spacer(); Text("\(selectedIndex + 1) / \(ids.count)").font(.caption).foregroundStyle(.secondary); Spacer()
                Button(mode == .book ? "下一页 →" : "下一张 →") { step(1) }.disabled(selectedIndex >= ids.count - 1)
            }.padding(24)
        }
        .background(mode == .book ? Color.primary.opacity(0.035) : .clear)
    }
    private func step(_ delta: Int) { guard !ids.isEmpty else { return }; selected = ids[min(ids.count - 1, max(0, selectedIndex + delta))] }
    private func freezeMotion() { if let started { phase += Date().timeIntervalSince(started) / AlbumWallLayout.secondsPerTile; self.started = nil } }
    private func resumeMotion() { if showingWall && !paused && !dragging && started == nil { started = Date() } }
    private func wakeControls() {
        controls = true; hideControls?.cancel()
        guard showingWall else { return }
        hideControls = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2.2)) } catch { return }
            guard !Task.isCancelled else { return }; controls = false
        }
    }
}
