import AppKit
import Foundation

/// Backdrop a recording is composited over at export time. Mirrors the
/// screenshot Beautify feature: presets, not a free-form picker.
enum VideoBackdrop: Hashable, Identifiable, Codable {
    case gradient(BeautifyStyle)
    case bundled(String)   // resource name, e.g. "sonoma-horizon"
    case wallpaper         // the user's current desktop wallpaper
    case color(RGBA)       // solid fill, rendered as a plain layer color
    case customImage(URL)  // user-chosen image file, aspect-filled

    /// Curated macOS-style set shipped in Resources/Wallpapers (from the
    /// Recordly project — attribution required in UI + README).
    static let bundledWallpaperNames: [String] = [
        "sequoia-blue-orange", "sequoia-blue",
        "sonoma-clouds", "sonoma-dark", "sonoma-evening",
        "sonoma-horizon", "sonoma-light",
        "tahoe-dark", "tahoe-light",
        "ventura-dark", "ventura"
    ]

    /// Menu layout for the export pickers: gradients, bundled wallpapers,
    /// then the live desktop wallpaper.
    static let pickerGroups: [(label: String, options: [VideoBackdrop])] = [
        ("Gradients", BeautifyStyle.allCases.map { .gradient($0) }),
        ("Wallpapers", bundledWallpaperNames.map { .bundled($0) }),
        ("Desktop", [.wallpaper])
    ]

    var id: String {
        switch self {
        case .gradient(let style): "gradient-\(style.rawValue)"
        case .bundled(let name): "bundled-\(name)"
        case .wallpaper: "wallpaper"
        case .color: "color"
        case .customImage(let url): "custom-\(url.path)"
        }
    }

    var title: String {
        switch self {
        case .gradient(let style): style.title
        case .bundled(let name):
            name.split(separator: "-").map(\.capitalized).joined(separator: " ")
        case .wallpaper: "Desktop Wallpaper"
        case .color: "Color"
        case .customImage: "Custom Image"
        }
    }

    /// The image drawn behind the video; nil for gradients (drawn as a
    /// CAGradientLayer instead) and when the wallpaper can't be read.
    func resolveImage(for screen: NSScreen?) -> NSImage? {
        switch self {
        case .gradient:
            nil
        case .bundled(let name):
            SniprAssets.wallpaper(named: name)
        case .wallpaper:
            (screen ?? NSScreen.main)
                .flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
                .flatMap { NSImage(contentsOf: $0) }
        case .color:
            nil
        case .customImage(let url):
            NSImage(contentsOf: url)
        }
    }
}

extension VideoBackdrop {
    static let defaultsKey = "videoExportBackdrop"

    static func loadSelection(from defaults: UserDefaults = .standard) -> VideoBackdrop? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(VideoBackdrop.self, from: data)
    }

    static func saveSelection(_ backdrop: VideoBackdrop?, to defaults: UserDefaults = .standard) {
        guard let backdrop, let data = try? JSONEncoder().encode(backdrop) else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        defaults.set(data, forKey: defaultsKey)
    }
}
