import Foundation

/// Token-substitution helper for capture filenames. Tokens supported:
/// `{date}`, `{time}`, `{app}`, `{window}`, `{w}`, `{h}`, `{seq}`. Missing
/// values resolve to empty strings; the result is whitespace-collapsed and
/// sanitized for filesystem use. The file extension is appended at the end
/// based on the chosen capture format.
enum CaptureFilenameTemplate {
    static let defaultTemplate = "Snipr {date} {time}"

    static func expand(
        template: String,
        date: Date,
        appName: String?,
        windowTitle: String?,
        pixelSize: CGSize,
        sequence: Int,
        fileExtension: String,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let dateString = Self.dateFormatter(timeZone: timeZone).string(from: date)
        let timeString = Self.timeFormatter(timeZone: timeZone).string(from: date)

        var output = template
        output = output.replacingOccurrences(of: "{date}", with: dateString)
        output = output.replacingOccurrences(of: "{time}", with: timeString)
        output = output.replacingOccurrences(of: "{app}", with: appName ?? "")
        output = output.replacingOccurrences(of: "{window}", with: windowTitle ?? "")
        output = output.replacingOccurrences(of: "{w}", with: String(Int(pixelSize.width.rounded())))
        output = output.replacingOccurrences(of: "{h}", with: String(Int(pixelSize.height.rounded())))
        output = output.replacingOccurrences(of: "{seq}", with: String(format: "%04d", sequence))

        let collapsed = collapseWhitespace(output)
        let sanitized = sanitize(collapsed)
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Snipr" : trimmed
        return "\(base).\(fileExtension)"
    }

    private static func dateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func timeFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH-mm-ss"
        return formatter
    }

    /// Replace runs of whitespace with a single space — `Snipr  {date}` with
    /// no `{date}` value would otherwise leave a double space.
    private static func collapseWhitespace(_ string: String) -> String {
        let components = string.split(whereSeparator: { $0.isWhitespace })
        return components.joined(separator: " ")
    }

    /// Strip filesystem-hostile characters. Keeping this minimal — Apple's
    /// HFS+/APFS only forbid `/` and `:`, but Windows-friendly downstream
    /// users tend to choke on the wider set. Better to write a clean name
    /// than wedge sync clients.
    private static func sanitize(_ string: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return String(String.UnicodeScalarView(string.unicodeScalars.map { scalar in
            forbidden.contains(scalar) ? Unicode.Scalar(0x2D)! : scalar
        }))
    }
}
