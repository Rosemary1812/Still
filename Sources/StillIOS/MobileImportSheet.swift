import SwiftUI
import PhotosUI

struct MobileImportSheet: View {
    var album: ContactAlbum?
    var onCreated: (ContactAlbum) -> Void = { _ in }
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var photos: PhotoRepository
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selection: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var completed = 0
    @State private var error: String?
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                if album == nil {
                    Section("相册名称") {
                        TextField("给这段时光起个名字", text: $name).accessibilityIdentifier("albumNameField")
                    }
                }
                Section {
                    PhotosPicker(selection: $selection, maxSelectionCount: 100, selectionBehavior: .ordered, matching: .images) {
                        Label(selection.isEmpty ? "选择照片" : "已选择 \(selection.count) 张，点此更改", systemImage: "photo.on.rectangle")
                    }.accessibilityIdentifier("choosePhotos")
                } footer: {
                    Text("照片会保存一份在 Still 中，原图保持不变。每次最多选择 100 张。")
                }
                if importing {
                    Section {
                        ProgressView(value: Double(completed), total: Double(max(1, selection.count))) {
                            Text("正在导入 \(completed) / \(selection.count)")
                        }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .disabled(importing)
            .navigationTitle(album == nil ? "新建相册" : "添加照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { importTask?.cancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(album == nil ? "创建" : "添加") { startImport() }
                        .disabled(importing || selection.isEmpty || (album == nil && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        .accessibilityIdentifier("saveAlbum")
                }
            }
            .interactiveDismissDisabled(importing)
            .onDisappear { importTask?.cancel() }
        }
    }

    private func startImport() {
        importing = true
        completed = 0
        error = nil
        importTask = Task { @MainActor in
            defer { importing = false }
            do {
                var ids: [String] = []
                for item in selection {
                    try Task.checkCancellation()
                    ids.append(try await photos.importPickerItem(item))
                    completed += 1
                }
                try Task.checkCancellation()
                if let album {
                    store.add(ids: ids, to: album)
                } else if let created = store.createAlbum(name: name, ids: ids) {
                    onCreated(created)
                }
                if let failure = store.error { error = failure }
                else { dismiss() }
            } catch is CancellationError {
                return
            } catch {
                self.error = "导入未完成，请检查网络或重新选择照片。\n\(error.localizedDescription)"
            }
        }
    }
}
