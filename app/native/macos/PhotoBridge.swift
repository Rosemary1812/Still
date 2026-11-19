import AppKit
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

public typealias PhotoReply = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void

// PHPicker grants access only to the user's selection. No whole-library permission is needed.
private final class PhotoSelection: NSObject, PHPickerViewControllerDelegate {
    private static var presented: PhotoSelection?
    private let window: NSWindow
    private let completion: (Result<[String], Error>) -> Void
    private init(picker: PHPickerViewController, completion: @escaping (Result<[String], Error>) -> Void) {
        self.window = NSWindow(contentViewController: picker)
        self.completion = completion
        super.init()
        picker.delegate = self
    }
    static func begin(completion: @escaping (Result<[String], Error>) -> Void) {
        guard let owner = NSApp.keyWindow ?? NSApp.mainWindow, presented == nil else {
            completion(.failure(NSError(domain: "Still", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先关闭已打开的选择器，再试一次。"])))
            return
        }
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selection = .ordered
        configuration.selectionLimit = 0
        let picker = PHPickerViewController(configuration: configuration)
        let selection = PhotoSelection(picker: picker, completion: completion)
        presented = selection
        selection.window.title = "从 Apple 照片添加"
        selection.window.styleMask.remove(.closable)
        selection.window.setContentSize(NSSize(width: 720, height: 520))
        owner.beginSheet(selection.window)
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.delegate = nil
        window.sheetParent?.endSheet(window)
        window.orderOut(nil)
        Self.presented = nil
        export(results[...], files: [])
    }

    private func export(_ items: ArraySlice<PHPickerResult>, files: [String]) {
        guard let item = items.first else {
            completion(.success(files))
            return
        }
        item.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
            do {
                guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
                let path = try Self.exportImage(url).path
                self.export(items.dropFirst(), files: files + [path])
            } catch {
                for path in files { try? FileManager.default.removeItem(atPath: path) }
                self.completion(.failure(error))
            }
        }
    }
    fileprivate static func exportImage(_ url: URL) throws -> URL {
        guard let image = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(image) else {throw CocoaError(.fileReadCorruptFile)}
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("still-import-" + UUID().uuidString)
        if [UTType.jpeg.identifier, UTType.png.identifier, UTType.gif.identifier, UTType.webP.identifier].contains(type as String) {
            try FileManager.default.copyItem(at: url, to: out)
        } else {
            let opts: [CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true]
            guard let frame=CGImageSourceCreateThumbnailAtIndex(image,0,opts as CFDictionary), let dest=CGImageDestinationCreateWithURL(out as CFURL,UTType.jpeg.identifier as CFString,1,nil) else {throw CocoaError(.fileReadCorruptFile)}
            CGImageDestinationAddImage(dest,frame,[kCGImageDestinationLossyCompressionQuality:0.95] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { try? FileManager.default.removeItem(at:out); throw CocoaError(.fileWriteUnknown) }
        }
        return out
    }
}

@_cdecl("contactsheet_choose_photo")
public func choosePhoto(_ context: UnsafeMutableRawPointer?, _ reply: @escaping PhotoReply) {
    DispatchQueue.main.async {
        PhotoSelection.begin { result in
            do {
                let json = try JSONEncoder().encode(result.get()); String(decoding: json, as: UTF8.self).withCString {reply($0,nil,context)}
            } catch {error.localizedDescription.withCString {reply(nil,$0,context)}}
        }
    }
}

// Dropped files arrive as they are on disk; formats only Apple's decoders read become JPEG at `destination`.
@_cdecl("contactsheet_export_image")
public func exportImage(_ source: UnsafePointer<CChar>, _ destination: UnsafePointer<CChar>) -> Bool {
    guard let exported = try? PhotoSelection.exportImage(URL(fileURLWithPath: String(cString: source))) else { return false }
    do { try FileManager.default.moveItem(at: exported, to: URL(fileURLWithPath: String(cString: destination))); return true }
    catch { try? FileManager.default.removeItem(at: exported); return false }
}
