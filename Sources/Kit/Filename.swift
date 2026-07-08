import Foundation

/// Filename hygiene for writing attachments to disk. PDF embedded-file names can
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

    /// Return a name not already in `taken`, inserting the result. Collisions get
    /// a numeric suffix before the extension: `report.pdf` → `report 2.pdf`.
    public static func deduplicated(_ name: String, taken: inout Set<String>) -> String {
        if taken.insert(name).inserted { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        var i = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            if taken.insert(candidate).inserted { return candidate }
            i += 1
        }
    }
}
