#!/usr/bin/env swift

import AppKit
import Foundation

enum BrandAssetGenerator {
    static let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    static let assetsRoot = repoRoot.appendingPathComponent("Sources/TypoFixr/Assets.xcassets", isDirectory: true)
    static let resourcesRoot = repoRoot.appendingPathComponent("Sources/TypoFixr/Resources", isDirectory: true)

    static func run() throws {
        try createDirectories()
        try writeCatalogMetadata()
        try writeAccentColor()
        try writeBrandMarkAssets()
        try writeMenuBarAssets()
        try writeAppIconAssets()
    }

    private static func createDirectories() throws {
        try FileManager.default.createDirectory(at: assetsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assetsRoot.appendingPathComponent("AppIcon.appiconset"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assetsRoot.appendingPathComponent("BrandMark.imageset"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assetsRoot.appendingPathComponent("MenuBarMark.imageset"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assetsRoot.appendingPathComponent("AccentColor.colorset"), withIntermediateDirectories: true)
    }

    private static func writeCatalogMetadata() throws {
        let contents = """
        {
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        try contents.write(to: assetsRoot.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    }

    private static func writeAccentColor() throws {
        let contents = """
        {
          "colors" : [
            {
              "color" : {
                "color-space" : "srgb",
                "components" : {
                  "alpha" : "1.000",
                  "blue" : "0.930",
                  "green" : "0.440",
                  "red" : "0.140"
                }
              },
              "idiom" : "universal"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        try contents.write(
            to: assetsRoot.appendingPathComponent("AccentColor.colorset/Contents.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func writeBrandMarkAssets() throws {
        let imageSetURL = assetsRoot.appendingPathComponent("BrandMark.imageset", isDirectory: true)
        let sizes: [(name: String, side: CGFloat, scale: String)] = [
            ("brand-mark.png", 128, "1x"),
            ("brand-mark@2x.png", 256, "2x"),
            ("brand-mark@3x.png", 384, "3x")
        ]

        for entry in sizes {
            let image = drawBrandIcon(side: entry.side, template: false)
            try writePNG(image: image, to: imageSetURL.appendingPathComponent(entry.name))
        }

        let contents = """
        {
          "images" : [
            {
              "filename" : "brand-mark.png",
              "idiom" : "universal",
              "scale" : "1x"
            },
            {
              "filename" : "brand-mark@2x.png",
              "idiom" : "universal",
              "scale" : "2x"
            },
            {
              "filename" : "brand-mark@3x.png",
              "idiom" : "universal",
              "scale" : "3x"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        try contents.write(to: imageSetURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    }

    private static func writeMenuBarAssets() throws {
        let imageSetURL = assetsRoot.appendingPathComponent("MenuBarMark.imageset", isDirectory: true)
        let sizes: [(name: String, side: CGFloat, scale: String)] = [
            ("menu-bar-mark.png", 18, "1x"),
            ("menu-bar-mark@2x.png", 36, "2x")
        ]

        for entry in sizes {
            let image = drawBrandIcon(side: entry.side, template: true)
            try writePNG(image: image, to: imageSetURL.appendingPathComponent(entry.name))
        }

        let contents = """
        {
          "images" : [
            {
              "filename" : "menu-bar-mark.png",
              "idiom" : "universal",
              "scale" : "1x"
            },
            {
              "filename" : "menu-bar-mark@2x.png",
              "idiom" : "universal",
              "scale" : "2x"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          },
          "properties" : {
            "template-rendering-intent" : "template"
          }
        }
        """
        try contents.write(to: imageSetURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    }

    private static func writeAppIconAssets() throws {
        let iconSetURL = assetsRoot.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
        let iconDefinitions: [(name: String, points: CGFloat, pixels: CGFloat)] = [
            ("icon_16x16.png", 16, 16),
            ("icon_16x16@2x.png", 16, 32),
            ("icon_32x32.png", 32, 32),
            ("icon_32x32@2x.png", 32, 64),
            ("icon_128x128.png", 128, 128),
            ("icon_128x128@2x.png", 128, 256),
            ("icon_256x256.png", 256, 256),
            ("icon_256x256@2x.png", 256, 512),
            ("icon_512x512.png", 512, 512),
            ("icon_512x512@2x.png", 512, 1024)
        ]

        for icon in iconDefinitions {
            let image = drawBrandIcon(side: icon.pixels, template: false)
            try writePNG(image: image, to: iconSetURL.appendingPathComponent(icon.name))
        }

        let contents = """
        {
          "images" : [
            { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
            { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
            { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
            { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
            { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
            { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
            { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
            { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
            { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
            { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        try contents.write(to: iconSetURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

        try generateICNS(from: iconSetURL)
    }

    private static func drawBrandIcon(side: CGFloat, template: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        let rect = CGRect(origin: .zero, size: CGSize(width: side, height: side))
        let inset = side * 0.08
        let iconRect = rect.insetBy(dx: inset, dy: inset)

        if template {
            NSColor.clear.setFill()
            rect.fill()
            drawTemplateMark(in: iconRect)
        } else {
            drawFullColorMark(in: iconRect)
        }

        image.unlockFocus()
        image.isTemplate = template
        return image
    }

    private static func drawFullColorMark(in rect: CGRect) {
        let basePath = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.24, yRadius: rect.height * 0.24)
        let gradient = NSGradient(
            colors: [
                NSColor(srgbRed: 0.14, green: 0.44, blue: 0.93, alpha: 1),
                NSColor(srgbRed: 0.11, green: 0.72, blue: 0.79, alpha: 1)
            ]
        )!
        gradient.draw(in: basePath, angle: -45)

        NSColor.white.withAlphaComponent(0.22).setStroke()
        basePath.lineWidth = max(2, rect.width * 0.015)
        basePath.stroke()

        let keyRect = CGRect(
            x: rect.minX + rect.width * 0.17,
            y: rect.minY + rect.height * 0.29,
            width: rect.width * 0.66,
            height: rect.height * 0.46
        )
        let keyPath = NSBezierPath(roundedRect: keyRect, xRadius: rect.width * 0.17, yRadius: rect.width * 0.17)
        NSColor.white.withAlphaComponent(0.95).setFill()
        keyPath.fill()

        let dotColor = NSColor(srgbRed: 0.16, green: 0.20, blue: 0.31, alpha: 0.24)
        dotColor.setFill()
        let dotSize = rect.width * 0.09
        let dotHeight = rect.height * 0.04
        for column in 0..<3 {
            let dotRect = CGRect(
                x: keyRect.minX + rect.width * 0.11 + CGFloat(column) * rect.width * 0.14,
                y: keyRect.maxY - rect.height * 0.13,
                width: dotSize,
                height: dotHeight
            )
            NSBezierPath(roundedRect: dotRect, xRadius: dotHeight / 2, yRadius: dotHeight / 2).fill()
        }

        let badgeRect = CGRect(
            x: rect.maxX - rect.width * 0.38,
            y: rect.minY + rect.height * 0.06,
            width: rect.width * 0.32,
            height: rect.width * 0.32
        )
        let badgePath = NSBezierPath(ovalIn: badgeRect)
        NSColor(srgbRed: 0.12, green: 0.75, blue: 0.45, alpha: 1).setFill()
        badgePath.fill()

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow.shadowBlurRadius = rect.width * 0.06
        shadow.shadowOffset = NSSize(width: 0, height: -rect.height * 0.02)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        badgePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        drawCheckmark(
            in: badgeRect,
            strokeColor: .white,
            lineWidth: max(6, rect.width * 0.06)
        )
    }

    private static func drawTemplateMark(in rect: CGRect) {
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let lineWidth = max(1.6, rect.width * 0.1)
        let keyRect = CGRect(
            x: rect.minX + rect.width * 0.12,
            y: rect.minY + rect.height * 0.22,
            width: rect.width * 0.58,
            height: rect.height * 0.5
        )
        let keyPath = NSBezierPath(roundedRect: keyRect, xRadius: rect.width * 0.14, yRadius: rect.width * 0.14)
        keyPath.lineWidth = lineWidth
        keyPath.stroke()

        for column in 0..<3 {
            let dashRect = CGRect(
                x: keyRect.minX + rect.width * 0.12 + CGFloat(column) * rect.width * 0.14,
                y: keyRect.midY - rect.height * 0.05,
                width: rect.width * 0.08,
                height: rect.height * 0.04
            )
            NSBezierPath(roundedRect: dashRect, xRadius: rect.height * 0.02, yRadius: rect.height * 0.02).fill()
        }

        let badgeRect = CGRect(
            x: rect.maxX - rect.width * 0.35,
            y: rect.minY + rect.height * 0.05,
            width: rect.width * 0.3,
            height: rect.width * 0.3
        )
        NSBezierPath(ovalIn: badgeRect).fill()
        drawCheckmark(in: badgeRect, strokeColor: .white, lineWidth: lineWidth)
    }

    private static func drawCheckmark(in rect: CGRect, strokeColor: NSColor, lineWidth: CGFloat) {
        let checkPath = NSBezierPath()
        checkPath.lineWidth = lineWidth
        checkPath.lineCapStyle = .round
        checkPath.lineJoinStyle = .round
        checkPath.move(to: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.midY))
        checkPath.line(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.24))
        checkPath.line(to: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.maxY - rect.height * 0.24))
        strokeColor.setStroke()
        checkPath.stroke()
    }

    private static func writePNG(image: NSImage, to url: URL) throws {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmapRep = NSBitmapImageRep(data: tiffData),
            let pngData = bitmapRep.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "BrandAssetGenerator", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create PNG data for \(url.lastPathComponent)"
            ])
        }

        try pngData.write(to: url)
    }

    private static func generateICNS(from iconSetURL: URL) throws {
        let temporaryIconsetURL = repoRoot.appendingPathComponent(".tmp/AppIcon.iconset", isDirectory: true)
        let temporaryRootURL = repoRoot.appendingPathComponent(".tmp", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryIconsetURL)
            try? FileManager.default.removeItem(at: temporaryRootURL)
        }
        try? FileManager.default.removeItem(at: temporaryIconsetURL)
        try FileManager.default.createDirectory(at: temporaryIconsetURL, withIntermediateDirectories: true)

        let pngFiles = try FileManager.default.contentsOfDirectory(at: iconSetURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }

        for file in pngFiles {
            let destination = temporaryIconsetURL.appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: file, to: destination)
        }

        let output = Process()
        output.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        output.arguments = ["-c", "icns", temporaryIconsetURL.path, "-o", resourcesRoot.appendingPathComponent("AppIcon.icns").path]
        try output.run()
        output.waitUntilExit()

        if output.terminationStatus != 0 {
            fputs("Warning: iconutil could not generate AppIcon.icns. Xcode builds will still use the asset catalog.\n", stderr)
        }
    }
}

do {
    try BrandAssetGenerator.run()
    print("Brand assets generated.")
} catch {
    fputs("Failed to generate brand assets: \(error)\n", stderr)
    exit(1)
}
