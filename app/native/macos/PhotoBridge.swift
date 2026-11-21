#if os(macOS)
import AppKit
#else
import UIKit
#endif
import AVFoundation
import ImageIO
import Photos
import PhotosUI
import UniformTypeIdentifiers

public typealias PhotoReply = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void

private struct Export: Encodable {
    let kind: String
    let file: String
    var motion: String?
    var poster: String?
    var duration: Double?
}

private struct Selection: Encodable {
    var files: [Export] = []
    var skipped = 0
}

private func liveIdentifier(_ url: URL) -> String? {
    if let image = CGImageSourceCreateWithURL(url as CFURL, nil),
       let props = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any] {
        return (props[kCGImagePropertyMakerAppleDictionary] as? [String: Any])?["17"] as? String
    }
    let metadata = AVURLAsset(url: url).metadata(forFormat: .quickTimeMetadata)
    return AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .quickTimeMetadataContentIdentifier).first?.stringValue
}

private func jpeg(_ frame: CGImage, at url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(dest, frame, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
}

private func imagePoster(_ source: URL, at output: URL) throws {
    let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                 kCGImageSourceCreateThumbnailWithTransform: true]
    guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
          let frame = CGImageSourceCreateThumbnailAtIndex(image, 0, opts as CFDictionary)
    else { throw CocoaError(.fileReadCorruptFile) }
    try jpeg(frame, at: output)
}

private func videoInfo(_ source: URL, poster: URL?) -> Double? {
    let asset = AVURLAsset(url: source)
    if let poster {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        if let frame = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            try? jpeg(frame, at: poster)
        }
    }
    let seconds = asset.duration.seconds
    return seconds.isFinite && seconds > 0 ? seconds : nil
}

private func writeResource(_ resource: PHAssetResource, to url: URL) async throws {
    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = true
    try await withCheckedThrowingContinuation { (reply: CheckedContinuation<Void, Error>) in
        PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
            if let error { reply.resume(throwing: error) } else { reply.resume() }
        }
    }
}

private func copyRepresentation(_ provider: NSItemProvider, type: UTType, directory: URL, name: String) async throws -> URL {
    // The provider's file expires when the callback returns.
    try await withCheckedThrowingContinuation { reply in
        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { source, error in
            do {
                guard let source else { throw error ?? CocoaError(.fileReadUnknown) }
                let target = directory.appendingPathComponent(name).appendingPathExtension(source.pathExtension)
                try FileManager.default.copyItem(at: source, to: target)
                reply.resume(returning: target)
            } catch { reply.resume(throwing: error) }
        }
    }
}

private func liveExport(still: URL, motion: URL, poster: URL) throws -> Export {
    try imagePoster(still, at: poster)
    return Export(kind: "live", file: still.path, motion: motion.path, poster: poster.path, duration: videoInfo(motion, poster: nil))
}

#if os(iOS)
private func exportLive(_ live: PHLivePhoto, to directory: URL, poster: URL) async throws -> Export {
    let resources = PHAssetResource.assetResources(for: live)
    func pair(_ still: PHAssetResourceType, _ motion: PHAssetResourceType) -> (PHAssetResource, PHAssetResource)? {
        guard let photo = resources.first(where: { $0.type == still }),
              let movie = resources.first(where: { $0.type == motion }) else { return nil }
        return (photo, movie)
    }
    // Preserve the original pair when available. Never mix an edited still with an original movie.
    guard let (photo, movie) = pair(.photo, .pairedVideo) ?? pair(.fullSizePhoto, .fullSizePairedVideo)
    else { throw CocoaError(.fileReadCorruptFile) }
    func destination(_ name: String, _ resource: PHAssetResource) -> URL {
        directory.appendingPathComponent(name).appendingPathExtension((resource.originalFilename as NSString).pathExtension)
    }
    let still = destination("still", photo)
    let motion = destination("motion", movie)
    try await writeResource(photo, to: still)
    try await writeResource(movie, to: motion)
    return try liveExport(still: still, motion: motion, poster: poster)
}
#endif

private func export(_ provider: NSItemProvider, to directory: URL) async throws -> Export {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let poster = directory.appendingPathComponent("poster.jpg")
    #if os(iOS)
    if provider.canLoadObject(ofClass: PHLivePhoto.self) {
        let live: PHLivePhoto = try await withCheckedThrowingContinuation { reply in
            provider.loadObject(ofClass: PHLivePhoto.self) { object, error in
                if let live = object as? PHLivePhoto { reply.resume(returning: live) }
                else { reply.resume(throwing: error ?? CocoaError(.fileReadCorruptFile)) }
            }
        }
        return try await exportLive(live, to: directory, poster: poster)
    }
    #else
    // macOS cannot load PHLivePhoto as an NSItemProviderReading object.
    if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
       provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
        let still = try await copyRepresentation(provider, type: .image, directory: directory, name: "still")
        let motion = try await copyRepresentation(provider, type: .movie, directory: directory, name: "motion")
        if let id = liveIdentifier(still), id == liveIdentifier(motion) {
            return try liveExport(still: still, motion: motion, poster: poster)
        }
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.livePhoto.identifier) {
        let bundle = try await copyRepresentation(provider, type: .livePhoto, directory: directory, name: "live")
        let keys: Set<URLResourceKey> = [.contentTypeKey, .isRegularFileKey, .isSymbolicLinkKey]
        let contents = try FileManager.default.contentsOfDirectory(at: bundle, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        func resource(_ type: UTType) -> URL? {
            contents.first { url in
                guard let values = try? url.resourceValues(forKeys: keys) else { return false }
                return values.isRegularFile == true && values.isSymbolicLink != true && values.contentType?.conforms(to: type) == true
            }
        }
        guard let still = resource(.image), let motion = resource(.movie),
              let id = liveIdentifier(still), id == liveIdentifier(motion) else { throw CocoaError(.fileReadCorruptFile) }
        return try liveExport(still: still, motion: motion, poster: poster)
    }
    #endif
    let isMovie = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
    let type: UTType = isMovie ? .movie : .image
    let file = try await copyRepresentation(provider, type: type, directory: directory, name: "original")
    if isMovie {
        let duration = videoInfo(file, poster: poster)
        return Export(kind: "video", file: file.path, poster: FileManager.default.fileExists(atPath: poster.path) ? poster.path : nil, duration: duration)
    }
    // Some Mac providers offer only the still from a Live Photo.
    guard liveIdentifier(file) == nil else { throw CocoaError(.fileReadCorruptFile) }
    if let image = CGImageSourceCreateWithURL(file as CFURL, nil), let type = CGImageSourceGetType(image),
       [UTType.jpeg, .png, .gif, .webP].contains(where: { $0.identifier == type as String }) {
        return Export(kind: "photo", file: file.path)
    }
    try imagePoster(file, at: poster)
    return Export(kind: "photo", file: poster.path)
}

@MainActor
private final class PhotoSelection: NSObject, PHPickerViewControllerDelegate {
    private static var presented: PhotoSelection?
    #if os(macOS)
    private var window: NSWindow?
    #endif
    let directory: URL
    let completion: (Result<Selection, Error>) -> Void
    init(directory: URL, completion: @escaping (Result<Selection, Error>) -> Void) {
        self.directory = directory
        self.completion = completion
    }
    func begin() {
        #if os(macOS)
        let owner = NSApp.keyWindow ?? NSApp.mainWindow
        #else
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var owner = scene?.keyWindow?.rootViewController
        while let next = owner?.presentedViewController { owner = next }
        #endif
        guard let owner, Self.presented == nil else {
            completion(.failure(NSError(domain: "Still", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先关闭已打开的选择器，再试一次。"])))
            return
        }
        var config = PHPickerConfiguration()
        config.filter = .any(of: [.images, .videos, .livePhotos])
        config.preferredAssetRepresentationMode = .current
        config.selection = .ordered
        config.selectionLimit = 0
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        Self.presented = self
        #if os(macOS)
        let sheet = NSWindow(contentViewController: picker)
        sheet.title = "从 Apple 照片添加"
        sheet.styleMask.remove(.closable)
        sheet.setContentSize(NSSize(width: 720, height: 520))
        window = sheet
        owner.beginSheet(sheet)
        #else
        picker.modalPresentationStyle = .fullScreen
        owner.present(picker, animated: true)
        #endif
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.delegate = nil
        #if os(macOS)
        if let window { window.sheetParent?.endSheet(window); window.orderOut(nil) }
        #else
        picker.dismiss(animated: true)
        #endif
        Self.presented = nil
        Task {
            var selection = Selection()
            for (index, result) in results.enumerated() {
                do {
                    let media = try await export(result.itemProvider, to: directory.appendingPathComponent(String(index)))
                    selection.files.append(media)
                } catch { selection.skipped += 1 }
            }
            completion(.success(selection))
        }
    }
}

private func finish<T: Encodable>(_ value: Result<T, Error>, _ context: UnsafeMutableRawPointer?, _ reply: PhotoReply) {
    do {
        let json = try JSONEncoder().encode(value.get())
        String(decoding: json, as: UTF8.self).withCString { reply($0, nil, context) }
    } catch { error.localizedDescription.withCString { reply(nil, $0, context) } }
}

@_cdecl("contactsheet_choose_photo")
public func choosePhoto(_ directory: UnsafePointer<CChar>, _ context: UnsafeMutableRawPointer?, _ reply: @escaping PhotoReply) {
    let folder = URL(fileURLWithPath: String(cString: directory))
    DispatchQueue.main.async {
        PhotoSelection(directory: folder) { finish($0, context, reply) }.begin()
    }
}

@_cdecl("contactsheet_export_image")
public func exportImage(_ source: UnsafePointer<CChar>, _ destination: UnsafePointer<CChar>) -> Bool {
    do {
        try imagePoster(URL(fileURLWithPath: String(cString: source)), at: URL(fileURLWithPath: String(cString: destination)))
        return true
    } catch { return false }
}

@_cdecl("contactsheet_video_info")
public func getVideoInfo(_ source: UnsafePointer<CChar>, _ destination: UnsafePointer<CChar>) -> Double {
    videoInfo(URL(fileURLWithPath: String(cString: source)), poster: URL(fileURLWithPath: String(cString: destination))) ?? 0
}


@_cdecl("contactsheet_live_identifier")
public func getLiveIdentifier(_ source: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
    guard let id = liveIdentifier(URL(fileURLWithPath: String(cString: source))), !id.isEmpty else { return nil }
    return strdup(id)
}

@_cdecl("contactsheet_free_identifier")
public func freeIdentifier(_ id: UnsafeMutablePointer<CChar>) {
    free(id)
}
