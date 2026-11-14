import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

struct ImportView: View {
    let existing: ContactAlbum?
    let finished: (ContactAlbum)->Void
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var photos: PhotoRepository
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var ids: [String] = []
    @State private var coverID: String?
    @State private var sourceID: String?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var choosingFiles = false
    @State private var importTask: Task<Void, Never>?
    @State private var error: String?
    @State private var candidates: [PhotoCandidate] = []
    @State private var sources: [PhotoAlbumSource] = []
    var canRead: Bool { photos.authorization == .authorized || photos.authorization == .limited }
    var body: some View {
        VStack(spacing:0) {
            HStack { VStack(alignment:.leading,spacing:4) { Text(existing == nil ? "创建相册" : "添加照片").font(.title2.weight(.semibold)); Text("照片副本保存在本机，原始文件不会被修改。").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("取消") { importTask?.cancel(); dismiss() }.keyboardShortcut(.cancelAction) }.padding(22)
            Divider()
            HStack(alignment:.top,spacing:0) {
                VStack(alignment:.leading,spacing:16) {
                    if existing == nil { TextField("相册名称",text:$name).textFieldStyle(.roundedBorder) }
                    Button { choosingFiles = true } label: { Label("从文件导入…", systemImage: "folder") }.disabled(busy)
                    PhotosPicker(selection:$pickerItems, selectionBehavior:.ordered, matching:.images, photoLibrary:.shared()) { Label("从 Apple 照片选择…",systemImage:"photo.on.rectangle") }.disabled(busy)
                    Text("可选择本地图片，或从 Apple 照片中导入。").font(.caption).foregroundStyle(.secondary)
                    if canRead {
                        Button("所有照片") { sourceID = nil; reload() }
                        ScrollView { VStack(alignment:.leading,spacing:10) { ForEach(sources) { source in Button { sourceID = source.id; reload() } label:{ Text("\(source.title) (\(source.count))").lineLimit(2).frame(maxWidth:.infinity,alignment:.leading) }.buttonStyle(.plain).foregroundStyle(sourceID == source.id ? Color.accentColor : .primary) } } }
                        if sourceID != nil { Button("选择整本相册") { for item in candidates where !ids.contains(item.id) { ids.append(item.id) }; if coverID == nil { coverID = ids.first } } }
                    } else {
                        Button("允许读取照片图库") { Task { await photos.requestAccess(); reload() } }
                        if photos.authorization == .denied || photos.authorization == .restricted {
                            Text("Library access is unavailable. You can still use Select Photos, or change access in System Settings → Privacy & Security → Photos.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }.padding(20).frame(width:230)
                Divider()
                ScrollView {
                    if candidates.isEmpty && ids.isEmpty { ContentUnavailableView("选择照片",systemImage:"photo.on.rectangle.angled",description:Text("选中的照片会显示在这里。")) }
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:105,maximum:150))],spacing:12) {
                        ForEach(visibleIDs,id:\.self) { id in
                            VStack(spacing:5) {
                                AssetImage(id:id,fit:false).aspectRatio(1,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:4))
                                    .overlay(alignment:.topTrailing) { if let index = ids.firstIndex(of:id) { Text("\(index+1)").font(.caption.bold()).padding(6).background(Color.accentColor,in:Circle()).foregroundStyle(.white).padding(5) } }
                                    .overlay { RoundedRectangle(cornerRadius:4).stroke(ids.contains(id) ? Color.accentColor : .clear,lineWidth:2) }
                                    .onTapGesture { toggle(id) }
                                if ids.contains(id) { Button(coverID == id ? "封面 ✓" : "设为封面") { coverID = id }.font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary) }
                            }
                        }
                    }.padding(20)
                }
            }.disabled(busy)
            Divider()
            HStack {
                if busy { ProgressView().controlSize(.small); Text("正在导入…") }
                else { Text("\(ids.count) 张已选").foregroundStyle(.secondary) }
                if let error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(3) }
                Spacer()
                Button(existing == nil ? "创建相册" : "添加照片") { beginSave() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(busy || ids.isEmpty || (existing == nil && name.nonEmpty == nil))
            }.padding(18)
        }.frame(width:780,height:580)
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else { return }
                busy = true; error = nil; importTask?.cancel()
                importTask = Task {
                    var failures: [String] = []
                    for url in urls {
                        if Task.isCancelled { return }
                        do {
                            let id = try await photos.importFile(url)
                            if !ids.contains(id) { ids.append(id) }
                        } catch { if Task.isCancelled { return }; failures.append(url.lastPathComponent) }
                    }
                    guard !Task.isCancelled else { return }
                    if coverID == nil { coverID = ids.first }
                    if !failures.isEmpty { error = "无法导入：" + failures.prefix(3).joined(separator: "、") + (failures.count > 3 ? " 等 \(failures.count) 个文件" : "") }
                    busy = false
                }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .onAppear { reload() }
        .onDisappear { importTask?.cancel() }
        .onChange(of:photos.revision) { _,_ in reload() }
        .onChange(of:pickerItems) { _,items in
            guard !items.isEmpty else { return }; busy = true; error = nil
            importTask?.cancel()
            importTask = Task {
                var failures = 0
                for item in items { if Task.isCancelled { return }; do { let id = try await photos.importPickerItem(item); guard !Task.isCancelled else { return }; if !ids.contains(id) { ids.append(id) } } catch { failures += 1 } }
                guard !Task.isCancelled else { return }
                if coverID == nil { coverID = ids.first }
                if failures > 0 { error = "\(failures) photos could not be loaded. Try again when available in Photos." }
                pickerItems = []; busy = false
            }
        }
    }
    var visibleIDs: [String] {
        let available = canRead ? candidates.map(\.id) : []
        let known = Set(available)
        return available + ids.filter { !known.contains($0) }
    }
    func reload() { if canRead { sources = photos.albums(); candidates = photos.assets(in:sourceID) } else { sources = []; candidates = [] } }
    func toggle(_ id:String) { if ids.contains(id) { ids.removeAll { $0 == id }; if coverID == id { coverID = ids.first } } else { ids.append(id); if coverID == nil { coverID = id } } }
    func beginSave() {
        busy = true; error = nil
        importTask = Task {
            do {
                var copies: [String: String] = [:]
                for id in ids { try Task.checkCancellation(); copies[id] = try await photos.managedCopy(id: id) }
                try Task.checkCancellation()
                let imported = ids.compactMap { copies[$0] }
                if let existing {
                    store.add(ids: imported, to: existing)
                    if store.error == nil { finished(existing); dismiss() }
                } else if let album = store.createAlbum(name: name, ids: imported) {
                    if let coverID, let copied = copies[coverID] { store.setCover(id: copied, album: album) }
                    if store.error == nil { finished(album); dismiss() }
                }
                error = store.error
            } catch {
                if Task.isCancelled { return }
                self.error = "导入未完成：" + error.localizedDescription
            }
            busy = false
        }
    }
}
