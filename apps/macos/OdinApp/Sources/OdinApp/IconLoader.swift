import AppKit
import SwiftUI

enum IconLoader {

    static func appIcon(pointSize: Int = 512) -> NSImage? {
        loadFromBundle(
            imageset: "AppIcon.appiconset",
            baseName: "icon_\(pointSize)x\(pointSize)",
            fallbackBaseName: "icon_256x256"
        )
    }

    /// Loads the OdinLogo template image from the bundle resources.
    /// This bypasses the asset catalog (which SPM doesn't compile) and
    /// loads the loose OdinLogo.png file directly.
    static func logo() -> NSImage? {
        // Try the loose resource file first (added via .process("OdinLogo.png"))
        if let img = Bundle.module.image(forResource: "OdinLogo") {
            img.isTemplate = true
            return img
        }
        // Fallback: try the imageset directory
        let assetDir = Bundle.module.resourceURL?
            .appendingPathComponent("Assets.xcassets")
            .appendingPathComponent("OdinLogo.imageset")
        if let dir = assetDir {
            let url = dir.appendingPathComponent("logo.png")
            if let img = NSImage(contentsOf: url) {
                img.isTemplate = true
                return img
            }
        }
        return nil
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

struct OdinLogoImage: View {
    var height: CGFloat? = nil

    var body: some View {
        if let originalImage = IconLoader.logo() {
            if let height = height {
                let nsImage: NSImage = {
                    let copy = originalImage.copy() as! NSImage
                    let aspectRatio = originalImage.size.width / originalImage.size.height
                    copy.size = NSSize(width: height * aspectRatio, height: height)
                    return copy
                }()
                Image(nsImage: nsImage)
                    .renderingMode(.template)
            } else {
                Image(nsImage: originalImage)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
    }
}

