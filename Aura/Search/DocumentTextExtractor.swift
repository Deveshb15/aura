import Foundation
import AppKit
import UniformTypeIdentifiers

/// Pulls a plain-text representation out of a saved document so it's searchable
/// by its *contents*, not just its filename. Dispatches by type:
///
///   • PDF                      → PDFKit text layer (`PDFTextExtractor`)
///   • plain text / code / data → read the bytes directly (txt, md, csv, json,
///                                xml, yaml, source code, …)
///   • HTML                     → SwiftSoup strip, shared with the article
///                                extractor (safe off the main thread)
///   • RTF / RTFD / Word / ODT  → `NSAttributedString`'s built-in importers,
///                                forced to an explicit document type so the
///                                reader is deterministic and never falls into
///                                the WebKit-backed HTML path (that path is
///                                main-thread-only and would be unsafe here)
///   • everything else          → nil (iWork, spreadsheets, archives, binaries
///                                stay searchable by filename alone)
///
/// Synchronous and CPU-bound; callers offload it off the main actor (see
/// `DataStore.extractText`). Capped at 8 000 characters to match the PDF and
/// article extractors so the search corpus stays uniform.
enum DocumentTextExtractor {
    private static let maxCharacters = 8_000
    /// Skip pathologically large files — the in-memory readers below would
    /// otherwise pull a multi-hundred-MB blob into RAM for nothing.
    private static let maxByteSize = 32 * 1024 * 1024

    /// Rich formats AppKit imports *without* WebKit, each mapped to the explicit
    /// document type so the importer is deterministic (no content sniffing).
    private static let richTypes: [(UTType, NSAttributedString.DocumentType)] = {
        let specs: [(String, NSAttributedString.DocumentType)] = [
            ("public.rtf", .rtf),
            ("com.apple.rtfd", .rtfd),
            ("org.openxmlformats.wordprocessingml.document", .officeOpenXML),
            ("com.microsoft.word.doc", .docFormat),
            ("org.oasis-open.opendocument.text", .openDocument),
        ]
        return specs.compactMap { id, docType in UTType(id).map { ($0, docType) } }
    }()

    /// Best plain-text representation of `url`, or nil for formats with no text
    /// layer. `uti` is the stored Uniform Type Identifier (falls back to the
    /// path extension when absent or unrecognized).
    static func extractText(from url: URL, uti: String?, fileName: String?) -> String? {
        // Stored assets normally keep their original extension, but fall back to
        // the captured filename's extension if the on-disk copy lost it.
        let ext = (url.pathExtension.isEmpty
                   ? (fileName as NSString?)?.pathExtension
                   : url.pathExtension)?.lowercased() ?? ""
        let type = resolvedType(uti: uti, ext: ext)

        // 1) PDF — text layer via PDFKit (also covers image-only PDFs → nil).
        if (type?.conforms(to: .pdf) ?? false) || ext == "pdf" {
            return PDFTextExtractor.extractText(from: url)
        }

        // Guard runaway sizes for the readers below.
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxByteSize {
            return nil
        }

        // 2) HTML — strip tags with SwiftSoup (the article extractor's readability
        // pass), which is safe off the main thread. Checked before the generic
        // plain-text branch because `public.html` conforms to `public.text`.
        if (type?.conforms(to: .html) ?? false) || ext == "html" || ext == "htm" {
            guard let raw = decode(url) else { return nil }
            return ArticleExtractor.extractText(fromHTML: raw, url: url)
        }

        // 3) Rich documents — RTF / RTFD / Word (.doc/.docx) / OpenDocument.
        if let type, let docType = richTypes.first(where: { type.conforms(to: $0.0) })?.1 {
            return readAttributed(url, docType: docType)
        }
        if let docType = richDocType(forExtension: ext) {
            return readAttributed(url, docType: docType)
        }

        // 4) Plain text / source code / structured data — read directly.
        if (type?.conforms(to: .text) ?? false) || isPlainTextExtension(ext) {
            guard let raw = decode(url) else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return String(trimmed.prefix(maxCharacters))
        }

        // Unknown / binary → filename-only search.
        return nil
    }

    // MARK: - Helpers

    private static func resolvedType(uti: String?, ext: String) -> UTType? {
        if let uti, let type = UTType(uti) { return type }
        return ext.isEmpty ? nil : UTType(filenameExtension: ext)
    }

    /// Reads a rich document through AppKit's importer for an explicit type. The
    /// chosen types (RTF/RTFD/Word/ODT) parse without WebKit, so running here off
    /// the main actor is safe — only the HTML/webarchive importers need main.
    private static func readAttributed(_ url: URL, docType: NSAttributedString.DocumentType) -> String? {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: docType]
        guard let attr = try? NSAttributedString(url: url, options: options, documentAttributes: nil) else {
            return nil
        }
        let text = attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(maxCharacters))
    }

    /// Decodes a text file, auto-detecting the encoding (BOM/heuristics) and
    /// falling back to UTF-8 then a lossy UTF-8 read so an odd encoding never
    /// drops the whole file from search.
    private static func decode(_ url: URL) -> String? {
        var encoding = String.Encoding.utf8
        if let s = try? String(contentsOf: url, usedEncoding: &encoding) { return s }
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        if let data = try? Data(contentsOf: url) { return String(decoding: data, as: UTF8.self) }
        return nil
    }

    private static func richDocType(forExtension ext: String) -> NSAttributedString.DocumentType? {
        switch ext {
        case "rtf":  return .rtf
        case "rtfd": return .rtfd
        case "docx": return .officeOpenXML
        case "doc":  return .docFormat
        case "odt":  return .openDocument
        default:     return nil
        }
    }

    /// Extension fallback for plain-text-ish files whose UTI is missing or too
    /// generic to conform to `public.text` (e.g. extensionless config files).
    private static func isPlainTextExtension(_ ext: String) -> Bool {
        [
            "txt", "text", "md", "markdown", "log", "csv", "tsv",
            "json", "xml", "yaml", "yml", "toml", "ini", "conf", "css", "sql",
            "swift", "js", "ts", "py", "rb", "go", "rs", "java", "kt",
            "c", "h", "cpp", "hpp", "cc", "m", "mm", "sh", "bash", "zsh",
        ].contains(ext)
    }
}
