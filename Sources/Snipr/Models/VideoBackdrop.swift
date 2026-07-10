import AppKit

/// Backdrop a recording is composited over at export time. Mirrors the
/// screenshot Beautify feature: presets, not a free-form picker.
enum VideoBackdrop: Hashable, Identifiable {
    case gradient(BeautifyStyle)
    case bundled(String)   // resource name, e.g. "sonoma-horizon"
    case wallpaper         // the user's current desktop wallpaper

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
        }
    }

    var title: String {
        switch self {
        case .gradient(let style): style.title
        case .bundled(let name):
            name.split(separator: "-").map(\.capitalized).joined(separator: " ")
        case .wallpaper: "Desktop Wallpaper"
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
        }
    }
}
