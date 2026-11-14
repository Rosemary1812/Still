import AppKit
import Photos

public typealias PhotoReply = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void

@_cdecl("contactsheet_choose_photo")
public func choosePhoto(_ context: UnsafeMutableRawPointer?, _ reply: @escaping PhotoReply) {
    let lock = NSLock()
    var completed = false
    func finish(_ path: String?, _ error: String?) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        lock.unlock()
        if let path { path.withCString { reply($0, nil, context) } }
        else { (error ?? "No image was returned.").withCString { reply(nil, $0, context) } }
    }
    DispatchQueue.main.async {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            guard status == .authorized || status == .limited else {
                finish(nil, "Photo library access was not granted. Local images remain available.")
                return
            }
            let options = PHFetchOptions()
            options.fetchLimit = 1
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            guard let asset = PHAsset.fetchAssets(with: .image, options: options).firstObject else {
                finish(nil, "No readable images in the photo library.")
                return
            }
            let request = PHImageRequestOptions()
            request.deliveryMode = .highQualityFormat
            request.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset, targetSize: NSSize(width: 1600, height: 1600), contentMode: .aspectFit, options: request) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                guard let data = image?.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: data),
                      let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                    finish(nil, "The photo could not be loaded.")
                    return
                }
                do {
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("contactsheet-nsh-prototype", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let file = directory.appendingPathComponent(UUID().uuidString + ".jpg")
                    try jpeg.write(to: file, options: .atomic)
                    finish(file.path, nil)
                } catch { finish(nil, error.localizedDescription) }
            }
        }
    }
}
