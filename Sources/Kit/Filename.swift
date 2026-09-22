import Foundation

/// Filename hygiene for writing embedded files to disk. PDF embedded-file names can
/// contain path separators, leading dots, or be empty — none safe to write as-is.
/// Display keeps the original name; only disk paths go through here.
public enum Filename {

    /// Strip directory components and characters that would escape the target
    /// directory or hide the file. Never returns an empty string.
    public static func sanitized(_ name: String) -> String {
        // lastPathComponent already discards directory components (and thus any
        // `../` traversal). Neutralize `:` (a legacy HFS separator) and strip
        // leading/trailing dots, slashes, and whitespace that would hide the file
        // or leave a bare separator.
        var s = (name as NSString).lastPathComponent
        s = s.replacingOccurrences(of: ":", with: "_")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/. \t\r\n"))
        return s.isEmpty ? "Untitled" : s
    }

    /// Return a name not already in `taken`, reserving the result. Collisions get
    /// a numeric suffix before the extension: `report.pdf` → `report 2.pdf`.
    ///
    /// Matching is case-insensitive because typical macOS volumes are, so
    /// `File.txt` and `file.txt` would collide on disk. `taken` holds the
    /// reserved names lowercased; the returned string keeps its original case.
    public static func deduplicated(_ name: String, taken: inout Set<String>) -> String {
        if taken.insert(name.lowercased()).inserted { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        var i = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            if taken.insert(candidate.lowercased()).inserted { return candidate }
            i += 1
        }
    }
}
