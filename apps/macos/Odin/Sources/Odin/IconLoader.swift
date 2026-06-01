import AppKit

/// Loads the app icon (used for the Dock tile and Finder preview).
/// The status-bar mark is now `EyeRuneMark` in `StageMark.swift`; this
/// loader is only here for `NSApp.applicationIconImage`.
enum IconLoader {
    static func appIcon(pointSize: Int = 512) -> NSImage? {
        loadFromBundle(
            imageset: "AppIcon.appiconset",
            baseName: "icon_\(pointSize)x\(pointSize)",
            fallbackBaseName: "icon_256x256"
        )
    }

    private static func loadFromBundle(
        imageset: String,
        baseName: String,
        fallbackBaseName: String? = nil
    ) -> NSImage? {
        let bundle = Bundle.module

        for suffix in ["@2x", ""] {
            let name = "\(baseName)\(suffix)"
            if let url = findFile(named: name, in: imageset, bundle: bundle),
               let img = NSImage(contentsOf: url) {
                return img
            }
        }

        if let fallback = fallbackBaseName {
            for suffix in ["@2x", ""] {
                let name = "\(fallback)\(suffix)"
                if let url = findFile(named: name, in: imageset, bundle: bundle),
                   let img = NSImage(contentsOf: url) {
                    return img
                }
            }
        }

        return nil
    }

    private static func findFile(named name: String, in imageset: String, bundle: Bundle) -> URL? {
        let assetDir = bundle.resourceURL?
            .appendingPathComponent("Assets.xcassets")
            .appendingPathComponent(imageset)

        if let dir = assetDir {
            let url = dir.appendingPathComponent("\(name).png")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return bundle.url(forResource: name, withExtension: "png")
    }
}
