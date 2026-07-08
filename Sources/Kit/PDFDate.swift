import Foundation

/// Parses PDF date strings of the form `D:YYYYMMDDHHmmSSZ` or
/// `D:YYYYMMDDHHmmSS+HH'mm'` (PDF spec §7.9.4). Only the year is required;
/// every finer component is optional and defaults per the spec. Returns nil on
/// malformed input rather than guessing.
public enum PDFDate {

    public static func parse(_ raw: String) -> Date? {
        var s = Substring(raw)
        if s.hasPrefix("D:") { s = s.dropFirst(2) }

        // Read fixed-width numeric components from the front of the string.
        func take(_ width: Int) -> Int? {
            guard s.count >= width else { return nil }
            let chunk = s.prefix(width)
            guard let value = Int(chunk), chunk.allSatisfy(\.isNumber) else { return nil }
            s = s.dropFirst(width)
            return value
        }

        guard let year = take(4) else { return nil }
        let month = take(2) ?? 1
        let day = take(2) ?? 1
        let hour = take(2) ?? 0
        let minute = take(2) ?? 0
        let second = take(2) ?? 0

        // Timezone: Z (UTC), or +/-HH'mm', or absent (treat as UTC).
        var timeZone = TimeZone(secondsFromGMT: 0)
        if let sign = s.first {
            switch sign {
            case "Z", "z":
                s = s.dropFirst()
            case "+", "-":
                s = s.dropFirst()
                // A sign must be followed by a real hour offset; a bare "+" is
                // malformed, not "UTC-ish".
                guard let tzHour = take(2) else { return nil }
                if s.first == "'" { s = s.dropFirst() }
                let tzMinute = take(2) ?? 0
                if s.first == "'" { s = s.dropFirst() }
                let offset = (tzHour * 3600 + tzMinute * 60) * (sign == "-" ? -1 : 1)
                timeZone = TimeZone(secondsFromGMT: offset)
            default:
                return nil
            }
        }

        // Anything left over means the input didn't match the grammar. The
        // parser documents nil-on-malformed, so honor that rather than silently
        // accepting trailing junk.
        guard s.isEmpty else { return nil }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        return components.date
    }
}
