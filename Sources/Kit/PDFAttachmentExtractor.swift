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

    /// Walks catalog → /Names → /EmbeddedFiles (a PDF *name tree*).
    public func extractAttachments() throws -> [RawAttachment] {
        guard doc.isUnlocked else { throw PDFError.notUnlocked }
        guard let catalog = doc.catalog else { return [] }

        var namesDict: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "Names", &namesDict),
              let names = namesDict else { return [] }

        var efNode: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(names, "EmbeddedFiles", &efNode),
              let root = efNode else { return [] }

        var results: [RawAttachment] = []
        var visited = Set<UnsafeRawPointer>()
        walkNameTree(root, into: &results, visited: &visited, depth: 0)
        return results
    }

    /// Belt-and-suspenders bound on the name-tree walk: a malformed or malicious
    /// PDF can contain a cyclic or absurdly deep /Kids graph, which would
    /// otherwise recurse forever or overflow the stack.
    private static let maxTreeDepth = 100

    // A name-tree node has EITHER a /Names leaf array OR a /Kids array (or both).
    private func walkNameTree(_ node: CGPDFDictionaryRef,
                              into results: inout [RawAttachment],
                              visited: inout Set<UnsafeRawPointer>,
                              depth: Int) {
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
                    if let att = attachment(from: fs, fallbackName: key) {
                        results.append(att)
                    }
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
                    walkNameTree(child, into: &results, visited: &visited, depth: depth + 1)
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
