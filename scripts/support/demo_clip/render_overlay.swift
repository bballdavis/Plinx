// Renders the 120 one-second title/timestamp overlay frames for
// generate_demo_clip.sh. Usage: swift render_overlay.swift <output-dir>
import AppKit
let out = CommandLine.arguments[1]
for sec in 0..<120 {
    let size = NSSize(width: 1280, height: 720)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 720, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.set(); NSRect(origin: .zero, size: size).fill()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.shadowOffset = NSSize(width: 0, height: -3); shadow.shadowBlurRadius = 8
    func draw(_ s: String, size fs: CGFloat, weight: NSFont.Weight, alpha: CGFloat, y: CGFloat) {
        var font = NSFont.systemFont(ofSize: fs, weight: weight)
        if let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: fs) { font = f }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(alpha), .shadow: shadow]
        let str = NSAttributedString(string: s, attributes: attrs)
        let w = str.size().width
        str.draw(at: NSPoint(x: (size.width - w) / 2, y: y))
    }
    draw("Plinx Demo Clip", size: 72, weight: .heavy, alpha: 1, y: 370)
    draw(String(format: "Fictional review media  •  %d:%02d", sec / 60, sec % 60), size: 34, weight: .semibold, alpha: 0.88, y: 310)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: String(format: "%@/f%03d.png", out, sec)))
}
