import Foundation

/// A displayable embedded file. Identity is a per-load UUID so SwiftUI lists and
/// the temp-file cache can key off it. `data` holds the extracted bytes; they're
/// only written to disk lazily (see the app's TempStore) on first preview/drag/save.
public struct EmbeddedFile: Identifiable, Sendable {
    public let id = UUID()
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

    public init(_ raw: RawEmbeddedFile) {
        self.init(name: raw.name, size: raw.size, modDate: raw.modDate, data: raw.data)
    }
}
