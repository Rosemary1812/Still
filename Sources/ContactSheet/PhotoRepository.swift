#if os(iOS)
import UIKit
typealias PlatformPhotoImage = UIImage
#else
import AppKit
typealias PlatformPhotoImage = NSImage
#endif
import Photos
import PhotosUI
import SwiftUI
import CryptoKit
import ImageIO

struct PhotoAlbumSource: Identifiable { let id: String; let title: String; let count: Int }
struct PhotoCandidate: Identifiable { let id: String; let date: Date?; let location: String? }
private final class ImageRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PlatformPhotoImage?, Never>?
    private var finished = false
    private var requestID: PHImageRequestID?
    func install(_ c: CheckedContinuation<PlatformPhotoImage?, Never>) { lock.lock(); if finished { lock.unlock(); c.resume(returning: nil) } else { continuation = c; lock.unlock() } }
    func setID(_ id: PHImageRequestID, manager: PHImageManager) { lock.lock(); requestID = id; let done = finished; lock.unlock(); if done { manager.cancelImageRequest(id) } }
    func finish(_ image: PlatformPhotoImage?) { lock.lock(); guard !finished else { lock.unlock(); return }; finished = true; let c = continuation; continuation = nil; lock.unlock(); c?.resume(returning: image) }
    func cancel(manager: PHImageManager) { lock.lock(); let id = requestID; lock.unlock(); if let id { manager.cancelImageRequest(id) }; finish(nil) }
}
@MainActor
final class PhotoRepository: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var revision = 0
    @Published var lastError: String?
    private let manager = PHCachingImageManager()
    private let cache = NSCache<NSString, PlatformPhotoImage>()
    private let importsURL: URL
    init(importsURL: URL? = nil, observeLibrary: Bool = true) {
        self.importsURL = importsURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ContactSheet/Imports", isDirectory: true)
        super.init(); cache.totalCostLimit = 80 * 1024 * 1024; cache.countLimit = 120
        if observeLibrary { PHPhotoLibrary.shared().register(self) }
    }
    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) { Task { @MainActor [weak self] in self?.refresh() } }
    func refresh() { authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite); cache.removeAllObjects(); manager.stopCachingImagesForAllAssets(); revision += 1 }
    func requestAccess() async { authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite); revision += 1 }
    private var canRead: Bool { authorization == .authorized || authorization == .limited }
    private func asset(_ id: String) -> PHAsset? {
        guard canRead, id.hasPrefix("photo:") else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [String(id.dropFirst(6))], options: nil).firstObject
    }
    func albums() -> [PhotoAlbumSource] {
        guard canRead else { return [] }; var result: [PhotoAlbumSource] = []
        for type in [PHAssetCollectionType.album, .smartAlbum] {
            PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: nil).enumerateObjects { collection, _, _ in
                let options = PHFetchOptions(); options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
                let count = PHAsset.fetchAssets(in: collection, options: options).count
                if count > 0 { result.append(PhotoAlbumSource(id: collection.localIdentifier, title: collection.localizedTitle ?? "Untitled Album", count: count)) }
            }
        }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func assets(in albumID: String?) -> [PhotoCandidate] {
        guard canRead else { return [] }
        let options = PHFetchOptions(); options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetched: PHFetchResult<PHAsset>
        if let albumID { guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject else { return [] }; fetched = PHAsset.fetchAssets(in: collection, options: options) }
        else { fetched = PHAsset.fetchAssets(with: options) }
        var result: [PhotoCandidate] = []; fetched.enumerateObjects { item, _, _ in result.append(Self.candidate(item)) }; return result
    }
    private nonisolated static func candidate(_ item: PHAsset) -> PhotoCandidate {
        let location = item.location.map { String(format: "%.4f, %.4f", $0.coordinate.latitude, $0.coordinate.longitude) }
        return PhotoCandidate(id: "photo:" + item.localIdentifier, date: item.creationDate, location: location)
    }
    func metadata(id: String) -> PhotoCandidate? {
        if let item = asset(id) { return Self.candidate(item) }
        if let url = localURL(id), FileManager.default.fileExists(atPath: url.path) { return PhotoCandidate(id: id, date: nil, location: nil) }; return nil
    }
    private func localURL(_ id: String) -> URL? {
        guard id.hasPrefix("local:") else { return nil }
        let name = String(id.dropFirst(6)); guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent, !name.contains("..") else { return nil }
        return importsURL.appendingPathComponent(name)
    }
    func importData(_ data: Data) throws -> String {
        try Self.persist(data, in: importsURL)
    }
    private nonisolated static func persist(_ data: Data, in importsURL: URL) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0, CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 32] as CFDictionary) != nil else { throw CocoaError(.fileReadCorruptFile) }
        let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".image"
        try FileManager.default.createDirectory(at: importsURL, withIntermediateDirectories: true)
        let url = importsURL.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }; return "local:" + name
    }
    func importFile(_ url: URL) async throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let destination = importsURL
        let id = try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return try Self.persist(data, in: destination)
        }.value
        try Task.checkCancellation()
        return id
    }
    private func importBytes(_ data: Data) async throws -> String {
        let destination = importsURL
        let id = try await Task.detached(priority: .userInitiated) { try Self.persist(data, in: destination) }.value
        try Task.checkCancellation()
        return id
    }
    func importPickerItem(_ item: PhotosPickerItem) async throws -> String {
        guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadUnknown) }
        return try await importBytes(data)
    }
    func managedCopy(id: String) async throws -> String {
        if let url = localURL(id) {
            guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
            return id
        }
        guard let asset = asset(id) else { throw CocoaError(.fileReadNoPermission) }
        let manager = manager
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            manager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                if let error = info?[PHImageErrorKey] as? Error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
            }
        }
        try Task.checkCancellation()
        return try await importBytes(data)
    }
    func loadImage(id: String, size: CGSize) async -> PlatformPhotoImage? {
        guard !Task.isCancelled else { return nil }
        if localURL(id) == nil {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard status == .authorized || status == .limited else { return nil }
        }
        let requestedRevision = revision
        let width = max(1, min(4096, size.width)), height = max(1, min(4096, size.height))
        let key = "\(id)-\(Int(width))-\(Int(height))-\(revision)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let image: PlatformPhotoImage?
        if let url = localURL(id) {
            image = await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height)] as CFDictionary) else { return nil as PlatformPhotoImage? }
                #if os(iOS)
                return UIImage(cgImage: cg)
                #else
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                #endif
            }.value
        } else if let asset = asset(id) {
            let state = ImageRequestState(); let manager = manager
            image = await withTaskCancellationHandler(operation: {
                await withCheckedContinuation { continuation in
                    state.install(continuation)
                    let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = true; options.deliveryMode = .highQualityFormat; options.resizeMode = .fast
                    let request = manager.requestImage(for: asset, targetSize: CGSize(width: width, height: height), contentMode: .aspectFit, options: options) { image, info in
                        if (info?[PHImageCancelledKey] as? Bool) == true || info?[PHImageErrorKey] != nil { state.finish(nil); return }
                        if (info?[PHImageResultIsDegradedKey] as? Bool) != true { state.finish(image) }
                    }; state.setID(request, manager: manager)
                }
            }, onCancel: { state.cancel(manager: manager) })
        } else { image = nil }
        guard !Task.isCancelled else { return nil }
        guard requestedRevision == revision else { return nil }
        if let image { cache.setObject(image, forKey: key, cost: Int(width * height * 4)) }; return image
    }
}
