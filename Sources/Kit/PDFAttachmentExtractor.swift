import CoreGraphics
import Foundation

/// A file embedded in a PDF's document-level `/EmbeddedFiles` name tree.
public struct RawAttachment {
    public let name: String
    public let size: Int
    public let modDate: Date?
    public let data: Data

    public init(name: String, size: Int, modDate: Date?, data: Data) {
        self.name = name
        self.size = size
        self.modDate = modDate
        self.data = data
    }
}

public enum PDFError: Error {
    case cannotOpen
    case wrongPassword
    case notUnlocked
}

/// UI-free core: opens a PDF via the CGPDF C API, handles password unlock, and
/// walks catalog → /Names → /EmbeddedFiles to pull out embedded files.
///
/// PDFKit deliberately can't do this — `PDFDocument` exposes no API for
/// document-level embedded files, so we drop to `CGPDFDocument`.
public final class PDFAttachmentExtractor {

    private let doc: CGPDFDocument

    public init(url: URL) throws {
        guard let d = CGPDFDocument(url as CFURL) else { throw PDFError.cannotOpen }
        self.doc = d
    }

    public var isEncrypted: Bool { doc.isEncrypted }
    public var isUnlocked: Bool { doc.isUnlocked }

    /// CGPDF checks the password against BOTH the user and owner password,
    /// so we don't need to know which kind it is. Returns true on success.
    public func unlock(password: String) -> Bool {
        if doc.isUnlocked { return true }
        return password.withCString { doc.unlockWithPassword($0) }
    }

    /// Collects every embedded file, from all three places a PDF can hide one:
    ///   1. document-level `/Names → /EmbeddedFiles` (portfolios / attachments),
    ///   2. page `/FileAttachment` annotations,
    ///   3. PDF 2.0 associated files (`/AF`) on the catalog and pages
    ///      (how e-invoices — ZUGFeRD/Factur-X — and PDF/A-3 embed data).
    /// A file referenced from more than one place (common in e-invoices) is
    /// returned once: first cheaply by file-spec object identity, then by a
    /// content fallback (identical name + bytes) in case CGPDF ever hands back
    /// distinct pointers for the same underlying object.
    public func extractAttachments() throws -> [RawAttachment] {
        guard doc.isUnlocked else { throw PDFError.notUnlocked }
        guard let catalog = doc.catalog else { return [] }

        var results: [RawAttachment] = []
        var visitedNodes = Set<UnsafeRawPointer>()   // name-tree cycle guard
        var seenSpecs = Set<UnsafeRawPointer>()       // file-spec de-dup

        // 1. Document-level /Names → /EmbeddedFiles name tree.
        var namesDict: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "Names", &namesDict), let names = namesDict {
            var efNode: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(names, "EmbeddedFiles", &efNode), let root = efNode {
                walkNameTree(root, visited: &visitedNodes, seen: &seenSpecs, into: &results)
            }
        }

        // 2. Catalog-level associated files (/AF).
        collectAssociatedFiles(from: catalog, seen: &seenSpecs, into: &results)

        // 3. Page-level: /FileAttachment annotations and page /AF.
        let pageCount = doc.numberOfPages
        if pageCount > 0 {
            for i in 1...pageCount {
                guard let page = doc.page(at: i),
                      let pageDict = page.dictionary else { continue }
                collectPageAnnotations(from: pageDict, seen: &seenSpecs, into: &results)
                collectAssociatedFiles(from: pageDict, seen: &seenSpecs, into: &results)
            }
        }

        return deduplicatedByContent(results)
    }

    /// Drop entries with the same name AND bytes as an earlier one — the content
    /// safety net behind the object-pointer dedup. Distinct files that merely
    /// share a name (or a size) are kept, since the bytes differ.
    ///
    /// Names are almost always unique, so we compare bytes only among entries
    /// that actually share a name — a uniquely named file never gets its payload
    /// hashed or compared.
    private func deduplicatedByContent(_ attachments: [RawAttachment]) -> [RawAttachment] {
        var payloadsByName: [String: [Data]] = [:]
        var result: [RawAttachment] = []
        result.reserveCapacity(attachments.count)
        for att in attachments {
            if let seen = payloadsByName[att.name] {
                if seen.contains(att.data) { continue }   // same name + bytes → duplicate
                payloadsByName[att.name]?.append(att.data)
            } else {
                payloadsByName[att.name] = [att.data]
            }
            result.append(att)
        }
        return result
    }

    /// Extract a file spec once (deduped by object identity) and append it.
    private func addAttachment(from filespec: CGPDFDictionaryRef,
                               fallbackName: String?,
                               seen: inout Set<UnsafeRawPointer>,
                               into results: inout [RawAttachment]) {
        let id = unsafeBitCast(filespec, to: UnsafeRawPointer.self)
        guard seen.insert(id).inserted else { return }
        if let att = attachment(from: filespec, fallbackName: fallbackName) {
            results.append(att)
        }
    }

    /// A file-spec array under `/AF` on the given dictionary (catalog or page).
    private func collectAssociatedFiles(from dict: CGPDFDictionaryRef,
                                        seen: inout Set<UnsafeRawPointer>,
                                        into results: inout [RawAttachment]) {
        var af: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dict, "AF", &af), let arr = af else { return }
        for k in 0..<CGPDFArrayGetCount(arr) {
            var filespec: CGPDFDictionaryRef?
            if CGPDFArrayGetDictionary(arr, k, &filespec), let fs = filespec {
                addAttachment(from: fs, fallbackName: nil, seen: &seen, into: &results)
            }
        }
    }

    /// `/FileAttachment` annotations on a page → their `/FS` file specs.
    private func collectPageAnnotations(from pageDict: CGPDFDictionaryRef,
                                        seen: inout Set<UnsafeRawPointer>,
                                        into results: inout [RawAttachment]) {
        var annots: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(pageDict, "Annots", &annots), let arr = annots else { return }
        for k in 0..<CGPDFArrayGetCount(arr) {
            var annot: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(arr, k, &annot), let a = annot else { continue }

            var subtype: UnsafePointer<Int8>?
            guard CGPDFDictionaryGetName(a, "Subtype", &subtype), let st = subtype,
                  String(cString: st) == "FileAttachment" else { continue }

            var filespec: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(a, "FS", &filespec), let fs = filespec {
                addAttachment(from: fs, fallbackName: nil, seen: &seen, into: &results)
            }
        }
    }

    /// Belt-and-suspenders bound on the name-tree walk: a malformed or malicious
    /// PDF can contain a cyclic or absurdly deep /Kids graph, which would
    /// otherwise recurse forever or overflow the stack.
    private static let maxTreeDepth = 100

    // A name-tree node has EITHER a /Names leaf array OR a /Kids array (or both).
    private func walkNameTree(_ node: CGPDFDictionaryRef,
                              visited: inout Set<UnsafeRawPointer>,
                              seen: inout Set<UnsafeRawPointer>,
                              into results: inout [RawAttachment],
                              depth: Int = 0) {
        guard depth < Self.maxTreeDepth else { return }
        // Skip nodes we've already visited (cycle guard). The node ref is an
        // opaque pointer; use its address as identity.
        let nodeID = unsafeBitCast(node, to: UnsafeRawPointer.self)
        guard visited.insert(nodeID).inserted else { return }

        // Leaf: /Names = [key1, filespec1, key2, filespec2, ...]
        var namesArray: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Names", &namesArray), let arr = namesArray {
            let count = CGPDFArrayGetCount(arr)
            var i = 0
            while i + 1 < count {
                var filespec: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(arr, i + 1, &filespec), let fs = filespec {
                    // The even index is the name-tree key — use it as the
                    // filename fallback when the filespec lacks /UF and /F.
                    let key = pdfArrayText(arr, i)
                    addAttachment(from: fs, fallbackName: key, seen: &seen, into: &results)
                }
                i += 2
            }
        }
        // Intermediate: /Kids = [childNode, childNode, ...]
        var kids: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Kids", &kids), let kidsArr = kids {
            for k in 0..<CGPDFArrayGetCount(kidsArr) {
                var kid: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(kidsArr, k, &kid), let child = kid {
                    walkNameTree(child, visited: &visited, seen: &seen, into: &results, depth: depth + 1)
                }
            }
        }
    }

    private func attachment(from filespec: CGPDFDictionaryRef, fallbackName: String?) -> RawAttachment? {
        // Filename: prefer /UF (unicode), fall back to /F, then the name-tree key.
        // (In well-formed PDFs /F and /UF name the same file — different encodings
        // of one filename — so pairing the chosen name with a specific /EF stream
        // isn't necessary and would only degrade unicode display in the common case.)
        let name = pdfText(filespec, "UF") ?? pdfText(filespec, "F") ?? fallbackName ?? "Untitled"

        // /EF embedded-file dict → /F (or /UF) is the actual file stream.
        var efDict: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(filespec, "EF", &efDict),
              let ef = efDict else { return nil }

        var stream: CGPDFStreamRef?
        if !CGPDFDictionaryGetStream(ef, "F", &stream) {
            _ = CGPDFDictionaryGetStream(ef, "UF", &stream)
        }
        guard let s = stream else { return nil }

        // CGPDFStreamCopyData applies standard filters (e.g. FlateDecode),
        // so `data` is the real file bytes for typical attachments.
        var format: CGPDFDataFormat = .raw
        guard let cf = CGPDFStreamCopyData(s, &format) else { return nil }
        let data = cf as Data

        // Optional metadata from the stream's /Params.
        var size = data.count
        var modDate: Date?
        if let sd = CGPDFStreamGetDictionary(s) {
            var params: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(sd, "Params", &params), let p = params {
                var sz: CGPDFInteger = 0
                if CGPDFDictionaryGetInteger(p, "Size", &sz) { size = Int(sz) }
                if let ds = pdfText(p, "ModDate") { modDate = PDFDate.parse(ds) }
            }
        }
        return RawAttachment(name: name, size: size, modDate: modDate, data: data)
    }

    private func pdfArrayText(_ arr: CGPDFArrayRef, _ index: Int) -> String? {
        var strRef: CGPDFStringRef?
        guard CGPDFArrayGetString(arr, index, &strRef), let s = strRef,
              let cf = CGPDFStringCopyTextString(s) else { return nil }
        return cf as String
    }

    private func pdfText(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var strRef: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dict, key, &strRef), let s = strRef,
              let cf = CGPDFStringCopyTextString(s) else { return nil }
        return cf as String
    }
}
