import Foundation
import UIKit

/// Renders original, deterministic artwork for the App Review demo library.
///
/// Every image is drawn on device from a title and a stable seed, so the demo
/// ships no third-party artwork, needs no network, and still presents posters,
/// backdrops, and episode stills that read as real media rather than blank
/// placeholders.
enum DemoFixtureArtwork {
    enum Kind: String {
        case poster
        case backdrop
        case still
    }

    private static let cacheLock = NSLock()
    private static var cache: [String: Data] = [:]

    /// Resolves a fixture artwork path such as `/artwork/poster/moonbound.png`.
    static func imageData(forPath path: String, title: String?) -> Data? {
        let components = path.split(separator: "/").map(String.init)
        guard components.count == 3,
              components[0] == "artwork",
              let kind = Kind(rawValue: components[1])
        else { return nil }

        let id = (components[2] as NSString).deletingPathExtension
        return imageData(kind: kind, id: id, title: title)
    }

    static func imageData(kind: Kind, id: String, title: String?) -> Data? {
        let cacheKey = "\(kind.rawValue)/\(id)"
        cacheLock.lock()
        if let cached = cache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let data = render(kind: kind, seed: stableSeed(id), title: title)

        cacheLock.lock()
        cache[cacheKey] = data
        cacheLock.unlock()
        return data
    }

    // MARK: - Rendering

    private struct Palette {
        let top: UIColor
        let bottom: UIColor
        let accent: UIColor
    }

    private static let palettes: [Palette] = [
        Palette(top: rgb(0x1F7A5C), bottom: rgb(0x0B2E2F), accent: rgb(0xC6F56B)),
        Palette(top: rgb(0x2B6CB0), bottom: rgb(0x112240), accent: rgb(0x9AE6FF)),
        Palette(top: rgb(0xD9673B), bottom: rgb(0x40182A), accent: rgb(0xFFD27A)),
        Palette(top: rgb(0x6B4FBB), bottom: rgb(0x1D1640), accent: rgb(0xF4B6FF)),
        Palette(top: rgb(0x2E9C9A), bottom: rgb(0x0D2A36), accent: rgb(0xFFE38A)),
        Palette(top: rgb(0xB8452F), bottom: rgb(0x2A1414), accent: rgb(0xFFB38A)),
        Palette(top: rgb(0x3E8E41), bottom: rgb(0x13281A), accent: rgb(0xE8FF9C)),
        Palette(top: rgb(0x1D5F8C), bottom: rgb(0x0A1A2B), accent: rgb(0x7DF0D0)),
    ]

    private static func render(kind: Kind, seed: UInt64, title: String?) -> Data? {
        let size: CGSize = switch kind {
        case .poster: CGSize(width: 480, height: 720)
        case .backdrop: CGSize(width: 1_600, height: 900)
        case .still: CGSize(width: 800, height: 450)
        }

        var generator = SeededGenerator(seed: seed)
        let palette = palettes[Int(seed % UInt64(palettes.count))]

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let image = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            let bounds = CGRect(origin: .zero, size: size)

            drawGradient(in: context, bounds: bounds, palette: palette)
            drawOrbs(in: context, bounds: bounds, palette: palette, generator: &generator)
            drawHills(in: context, bounds: bounds, palette: palette, generator: &generator)

            if kind == .poster, let title, !title.isEmpty {
                drawPosterTitle(title, in: bounds)
            }
        }

        return image.jpegData(compressionQuality: 0.86)
    }

    private static func drawGradient(in context: CGContext, bounds: CGRect, palette: Palette) {
        let colors = [palette.top.cgColor, palette.bottom.cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else {
            return
        }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.minX, y: bounds.minY),
            end: CGPoint(x: bounds.maxX * 0.4, y: bounds.maxY),
            options: [.drawsAfterEndLocation],
        )
    }

    private static func drawOrbs(
        in context: CGContext,
        bounds: CGRect,
        palette: Palette,
        generator: inout SeededGenerator,
    ) {
        let unit = min(bounds.width, bounds.height)
        for index in 0..<3 {
            let diameter = unit * CGFloat.random(in: 0.28...0.62, using: &generator)
            let center = CGPoint(
                x: bounds.width * CGFloat.random(in: 0.1...0.9, using: &generator),
                y: bounds.height * CGFloat.random(in: 0.08...0.5, using: &generator),
            )
            let rect = CGRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter,
            )
            let alpha: CGFloat = index == 0 ? 0.85 : 0.18
            context.setFillColor(palette.accent.withAlphaComponent(alpha).cgColor)
            context.fillEllipse(in: rect)
        }
    }

    private static func drawHills(
        in context: CGContext,
        bounds: CGRect,
        palette: Palette,
        generator: inout SeededGenerator,
    ) {
        for layer in 0..<2 {
            let baseline = bounds.height * (layer == 0 ? 0.62 : 0.74)
            let amplitude = bounds.height * CGFloat.random(in: 0.04...0.1, using: &generator)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: bounds.minX, y: bounds.maxY))
            path.addLine(to: CGPoint(x: bounds.minX, y: baseline))
            path.addCurve(
                to: CGPoint(x: bounds.maxX, y: baseline - amplitude),
                controlPoint1: CGPoint(x: bounds.width * 0.3, y: baseline - amplitude * 2),
                controlPoint2: CGPoint(x: bounds.width * 0.7, y: baseline + amplitude),
            )
            path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
            path.close()

            let shade = layer == 0 ? palette.bottom.withAlphaComponent(0.55) : palette.bottom.withAlphaComponent(0.92)
            context.setFillColor(shade.cgColor)
            context.addPath(path.cgPath)
            context.fillPath()
        }
    }

    private static func drawPosterTitle(_ title: String, in bounds: CGRect) {
        let inset = bounds.width * 0.09
        let baseFont = UIFont.systemFont(ofSize: bounds.width * 0.115, weight: .heavy)
        let font = baseFont.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 0) } ?? baseFont

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping

        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = CGSize(width: 0, height: 3)
        shadow.shadowBlurRadius = 8

        let attributed = NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph,
                .shadow: shadow,
            ],
        )
        let textWidth = bounds.width - inset * 2
        let measured = attributed.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil,
        )
        let textRect = CGRect(
            x: inset,
            // Keep the title inside the central band: browse rows crop posters
            // toward square, trimming roughly the outer 13% top and bottom.
            y: bounds.height * 0.8 - ceil(measured.height),
            width: textWidth,
            height: ceil(measured.height),
        )
        attributed.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    // MARK: - Determinism

    /// FNV-1a over the identifier, so artwork is stable across launches.
    private static func stableSeed(_ id: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1,
        )
    }
}

/// SplitMix64: a tiny deterministic generator for reproducible artwork.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
