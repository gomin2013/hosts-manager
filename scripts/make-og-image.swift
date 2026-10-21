// Social preview card (1200×630) for the website: app icon + name + tagline on the left, the -demo screenshot
// bleeding off the right edge. Re-run after scripts/capture-screenshots.sh.
// Usage: swift scripts/make-og-image.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let img = root.appendingPathComponent("docs/assets/img")
let size = NSSize(width: 1200, height: 630)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 630, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: navy to the icon's blue
NSGradient(colors: [NSColor(red: 0.05, green: 0.08, blue: 0.20, alpha: 1),
                    NSColor(red: 0.05, green: 0.27, blue: 0.75, alpha: 1)])!
    .draw(in: NSRect(origin: .zero, size: size), angle: 20)

// Screenshot, right side, rounded, cropped by the canvas edge
let shot = NSImage(contentsOf: img.appendingPathComponent("hm-main-dark.png"))!
let shotHeight: CGFloat = 470
let shotRect = NSRect(x: 600, y: (630 - shotHeight) / 2, width: shotHeight * shot.size.width / shot.size.height,
                      height: shotHeight)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSBezierPath(roundedRect: shotRect, xRadius: 14, yRadius: 14).addClip()
shot.draw(in: shotRect)
NSGraphicsContext.restoreGraphicsState()

// Icon, name, tagline, URL
NSImage(contentsOf: root.appendingPathComponent("Packaging/AppIcon-1024.png"))!
    .draw(in: NSRect(x: 52, y: 400, width: 150, height: 150))
/// Draws a text block whose bottom edge sits at `bottom` (unflipped context: draw(with:) top-aligns in its rect).
func text(_ string: String, _ font: NSFont, _ color: NSColor, x: CGFloat, bottom: CGFloat, width: CGFloat = 520) {
    let style = NSMutableParagraphStyle()
    style.lineHeightMultiple = 0.95
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color,
                                                                      .paragraphStyle: style])
    let height = ceil(attributed.boundingRect(with: NSSize(width: width, height: 1000),
                                              options: [.usesLineFragmentOrigin]).height)
    attributed.draw(with: NSRect(x: x, y: bottom, width: width, height: height), options: [.usesLineFragmentOrigin])
}
text("Hosts\nManager", .systemFont(ofSize: 66, weight: .bold), .white, x: 72, bottom: 214)
text("Edit /etc/hosts on your Mac, safely.\nFree, open source, with History and an AI Agent.",
     .systemFont(ofSize: 25, weight: .regular), NSColor.white.withAlphaComponent(0.85), x: 72, bottom: 112)
text("github.com/gomin2013/hosts-manager", .monospacedSystemFont(ofSize: 21, weight: .regular),
     NSColor.white.withAlphaComponent(0.6), x: 72, bottom: 52)

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: img.appendingPathComponent("og-image.png"))
print("Wrote docs/assets/img/og-image.png")
