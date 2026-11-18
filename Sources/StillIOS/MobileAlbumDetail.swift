import SwiftUI

private struct SelectedPhoto: Identifiable {
    let id: String
}

struct MobileAlbumDetail: View {
    let album: ContactAlbum
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var renaming = false
    @State private var name = ""
    @State private var deleting = false
    @State private var selectedPhoto: SelectedPhoto?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom, spacing: 18) {
                    MobileAlbumCover(album: album).frame(width: 112, height: 112)
                        .rotationEffect(.degrees(-3))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 8)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(album.name).font(.title2.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                        Text("\(album.photos.count) 张照片").font(.subheadline).foregroundStyle(.secondary)
                        Text(album.createdAt, format: .dateTime.year().month().day())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 12)
                if album.photos.isEmpty {
                    ContentUnavailableView("相册里还没有照片", systemImage: "photo.on.rectangle",
                                           description: Text("点击右上角添加照片。"))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                    ForEach(Array(store.orderedIDs(album: album).enumerated()), id: \.element) { entry in
                        Button { selectedPhoto = SelectedPhoto(id: entry.element) } label: {
                            MobilePhoto(id: entry.element, pixels: 450).aspectRatio(1, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("照片 \(entry.offset + 1)")
                        .accessibilityIdentifier("photo-\(entry.offset)")
                    }
                }
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("相册").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { importing = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("添加照片")
                Menu {
                    Button("重命名", systemImage: "pencil") { name = album.name; renaming = true }
                    Button("删除相册", systemImage: "trash", role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("相册选项")
            }
        }
        .sheet(isPresented: $importing) { MobileImportSheet(album: album) }
        .fullScreenCover(item: $selectedPhoto) { photo in
            MobilePhotoViewer(album: album, initialID: photo.id)
        }
        .alert("重命名相册", isPresented: $renaming) {
            TextField("相册名称", text: $name)
            Button("取消", role: .cancel) {}
            Button("保存") { store.rename(album: album, name: name) }
        }
        .confirmationDialog("删除「\(album.name)」？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除相册", role: .destructive) {
                store.delete(album: album)
                if store.error == nil { dismiss() }
            }
        } message: { Text("会移除这本相册，不会删除系统照片或其他相册中的照片。") }
    }
}

struct MobilePhotoViewer: View {
    let album: ContactAlbum
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String
    @State private var editing = false
    @State private var removing = false
    @State private var coverSaved = false

    init(album: ContactAlbum, initialID: String) {
        self.album = album
        _selectedID = State(initialValue: initialID)
    }

    private var ids: [String] { store.orderedIDs(album: album) }
    private var position: Int { (ids.firstIndex(of: selectedID) ?? 0) + 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $selectedID) {
                    ForEach(ids, id: \.self) { id in
                        MobilePhoto(id: id, fit: true, pixels: 2400).tag(id)
                            .accessibilityLabel("照片 \((ids.firstIndex(of: id) ?? 0) + 1)")
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .accessibilityIdentifier("photoPager")
                if let note = store.annotation(id: selectedID), !note.title.isEmpty || !note.descriptionText.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if !note.title.isEmpty { Text(note.title).font(.headline) }
                            if !note.descriptionText.isEmpty { Text(note.descriptionText).font(.body) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    }.frame(maxHeight: 160)
                }
                Button { editing = true } label: {
                    Label("写旁注", systemImage: "square.and.pencil").padding(16)
                }.accessibilityIdentifier("editAnnotation")
            }
            .background(.black).foregroundStyle(.white)
            .navigationTitle("\(position) / \(ids.count)").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("关闭照片")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("设为封面", systemImage: "rectangle.portrait") {
                            store.setCover(id: selectedID, album: album)
                            coverSaved = store.error == nil
                        }
                        Button("从相册移除", systemImage: "minus.circle", role: .destructive) { removing = true }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("照片选项")
                }
            }
            .sheet(isPresented: $editing) { MobileAnnotationEditor(id: selectedID) }
            .alert("已设为相册封面", isPresented: $coverSaved) { Button("好", role: .cancel) {} }
            .confirmationDialog("从这本相册移除照片？", isPresented: $removing, titleVisibility: .visible) {
                Button("移除照片", role: .destructive) {
                    let remaining = ids.filter { $0 != selectedID }
                    store.remove(ids: [selectedID], from: album)
                    guard store.error == nil else { return }
                    if let next = remaining.first { selectedID = next } else { dismiss() }
                }
            } message: { Text("系统照片和其他相册不受影响。") }
        }.tint(.white)
    }
}

private struct MobileAnnotationEditor: View {
    let id: String
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") { TextField("这一刻", text: $title).accessibilityIdentifier("annotationTitle") }
                Section("旁注") { TextEditor(text: $text).frame(minHeight: 200).accessibilityIdentifier("annotationBody") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("照片旁注").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let existing = store.annotation(id: id)
                        store.saveAnnotation(id: id, title: title, description: text,
                                             date: existing?.displayDate, location: existing?.locationText ?? "")
                        if let failure = store.error { error = failure } else { dismiss() }
                    }.accessibilityIdentifier("saveAnnotation")
                }
            }
            .onAppear {
                if let note = store.annotation(id: id) { title = note.title; text = note.descriptionText }
            }
        }.tint(.primary)
    }
}
