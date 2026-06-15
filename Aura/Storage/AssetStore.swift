import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Copies captured originals (images, files) onto disk under
/// `~/Library/Application Support/Aura/Assets/` and hands back a *relative*
/// path that gets stored in the database.
///
/// `Sendable`: the only stored state is the immutable `baseURL`; every method is
/// pure filesystem I/O. This lets the heavy disk writes run in `Task.detached`
/// off the main actor (see `DataStore.populateImage`) without capture warnings.
final class AssetStore: Sendable {
    let baseURL: URL

    struct Stored {
        var relativePath: String
        var uti: String?
        var byteSize: Int
        var fileName: String
    }

    init() throws {
        let support = try AppDatabase.supportDirectory()
        baseURL = support.appendingPathComponent("Assets", isDirectory: true)
        let fm = FileManager.default
        for subdir in ["img", "file", "og", "favicon", "logo"] {
            try fm.createDirectory(at: baseURL.appendingPathComponent(subdir), withIntermediateDirectories: true)
        }
    }

    func absoluteURL(for relativePath: String) -> URL {
        baseURL.appendingPathComponent(relativePath)
    }

    /// Writes raw image bytes, preserving the original encoding/extension.
    func storeImageData(_ data: Data) throws -> Stored {
        let ext = Self.imageExtension(for: data) ?? "png"
        let id = UUID().uuidString
        let relative = "img/\(id).\(ext)"
        try data.write(to: absoluteURL(for: relative), options: .atomic)
        return Stored(relativePath: relative,
                      uti: UTType(filenameExtension: ext)?.identifier,
                      byteSize: data.count,
                      fileName: "\(id).\(ext)")
    }

    /// Writes image bytes into a named subdirectory (e.g. "og", "favicon").
    func storeImage(_ data: Data, subdir: String) throws -> Stored {
        let ext = Self.imageExtension(for: data) ?? "png"
        let id = UUID().uuidString
        let relative = "\(subdir)/\(id).\(ext)"
        try data.write(to: absoluteURL(for: relative), options: .atomic)
        return Stored(relativePath: relative,
                      uti: UTType(filenameExtension: ext)?.identifier,
                      byteSize: data.count,
                      fileName: "\(id).\(ext)")
    }

    /// Copies a dropped file in (never references the original, which may move/delete).
    func storeFile(at url: URL) throws -> Stored {
        let id = UUID().uuidString
        let ext = url.pathExtension
        let relative = ext.isEmpty ? "file/\(id)" : "file/\(id).\(ext)"
        let dest = absoluteURL(for: relative)
        try FileManager.default.copyItem(at: url, to: dest)
        let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
        return Stored(relativePath: relative,
                      uti: UTType(filenameExtension: ext)?.identifier,
                      byteSize: size,
                      fileName: url.lastPathComponent)
    }

    func removeAsset(relativePath: String) {
        try? FileManager.default.removeItem(at: absoluteURL(for: relativePath))
    }

    /// Wipes every stored asset (used by "Clear All Data").
    func removeAllAssets() {
        let fm = FileManager.default
        for subdir in ["img", "file", "og", "favicon", "logo"] {
            let dir = baseURL.appendingPathComponent(subdir)
            try? fm.removeItem(at: dir)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Detects the preferred file extension for raw image data via ImageIO.
    static func imageExtension(for data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let uti = CGImageSourceGetType(source) else { return nil }
        return UTType(uti as String)?.preferredFilenameExtension
    }

    static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}
