import AppKit
import Foundation

enum SniprAssets {
    static func image(named name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return nil
    }

    static func wallpaper(named name: String) -> NSImage? {
        for bundle in [Bundle.main, Bundle.module] {
            if let url = bundle.url(forResource: name, withExtension: "jpg"),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }
}
