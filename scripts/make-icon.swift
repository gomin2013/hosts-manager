// Builds app artwork from Packaging/source/ (AI renders, see .claude/docs/design/logo/v1.1.0.md):
//   Packaging/AppIcon.icon  — Icon Composer document (open/edit in Xcode's Icon Composer.app)
//   Packaging/Assets.car    — compiled from AppIcon.icon by actool; macOS 26+ (CFBundleIconName)
//   Packaging/AppIcon.icns  — macOS 14–15 (CFBundleIconFile): mascot 128–1024 px, flat globe 16–64 px
// macOS 26 draws any legacy .icns inside a gray platter (verified: even full-bleed art); only an
// Icon Composer icon in Assets.car gets the system squircle + glass treatment.
//   Packaging/Mascot.png    — transparent mascot for README / release page (512 px, halo trimmed)
// Usage: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let packaging = root.appendingPathComponent("Packaging")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")

// MARK: - Pixel helpers (RGBA8, premultiplied)

func loadCGImage(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("can't read \(url.path)") }
    return image
}

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Rows/columns where at least `fraction` of pixels have alpha > `minAlpha` — finds the solid body, ignores fringe.
func solidBounds(_ image: CGImage, minAlpha: UInt8, fraction: Double) -> CGRect {
    let ctx = makeContext(image.width, image.height)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let (w, h, stride) = (image.width, image.height, ctx.bytesPerRow)
    var rowCounts = [Int](repeating: 0, count: h), colCounts = [Int](repeating: 0, count: w)
    for y in 0..<h {
        for x in 0..<w where pixels[y * stride + x * 4 + 3] > minAlpha {
            rowCounts[y] += 1; colCounts[x] += 1
        }
    }
    let rows = rowCounts.indices.filter { Double(rowCounts[$0]) > Double(w) * fraction }
    let cols = colCounts.indices.filter { Double(colCounts[$0]) > Double(h) * fraction }
    // CGContext rows are bottom-up; convert to image (top-down) coordinates for cropping.
    return CGRect(x: cols.first!, y: h - 1 - rows.last!, width: cols.last! - cols.first! + 1,
                  height: rows.last! - rows.first! + 1)
}

func png(_ image: CGImage, _ url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: - App icon

/// macOS grid: 824 px body centered on 1024, ~22.5% corner radius.
let iconSource = loadCGImage(packaging.appendingPathComponent("source/icon.png"))
// Inset 0.6% so the clip lands inside the render's own bevel, never on the noisy fringe.
let tile = solidBounds(iconSource, minAlpha: 250, fraction: 0.5).insetBy(dx: 8, dy: 8)
let mascotTile = iconSource.cropping(to: tile)!

func renderMascotIcon(_ size: Int) -> CGImage {
    let ctx = makeContext(size, size)
    ctx.interpolationQuality = .high
    let scale = CGFloat(size) / 1024
    let body = CGRect(x: 100, y: 100, width: 824, height: 824).applying(.init(scaleX: scale, y: scale))
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: 185 * scale, cornerHeight: 185 * scale, transform: nil))
    ctx.clip()
    ctx.draw(mascotTile, in: body)
    return ctx.makeImage()!
}

/// Flat version for 16–64 px, where the glass robot is unreadable: its tile colours + the visor's `network` globe.
func renderFlatIcon(_ size: Int) -> CGImage {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    let body = NSRect(x: 100, y: 100, width: 824, height: 824).applying(.init(scaleX: scale, y: scale))
    NSGradient(
        starting: NSColor(red: 0.18, green: 0.59, blue: 1.00, alpha: 1),   // #2E96FF — the robot tile's sky blue
        ending: NSColor(red: 0.18, green: 0.29, blue: 0.81, alpha: 1)      // #2D4BCF — its indigo corner
    )!.draw(in: NSBezierPath(roundedRect: body, xRadius: 185 * scale, yRadius: 185 * scale), angle: -90)
    let symbol = NSImage(systemSymbolName: "network", accessibilityDescription: nil)!
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 440 * scale, weight: .semibold)
            .applying(.init(paletteColors: [.white])))!
    symbol.draw(in: NSRect(x: body.midX - symbol.size.width / 2, y: body.midY - symbol.size.height / 2,
                           width: symbol.size.width, height: symbol.size.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for (pixels, suffix) in [(points, ""), (points * 2, "@2x")] {
        let image = pixels <= 64 ? renderFlatIcon(pixels) : renderMascotIcon(pixels)
        try png(image, iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try png(renderMascotIcon(1024), packaging.appendingPathComponent("AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", packaging.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

// MARK: - Icon Composer document → Assets.car (macOS 26+)

let iconDocument = packaging.appendingPathComponent("AppIcon.icon")
try? FileManager.default.removeItem(at: iconDocument)
try FileManager.default.createDirectory(at: iconDocument.appendingPathComponent("Assets"), withIntermediateDirectories: true)

// Full-bleed square layer: trim the render's own rounded corners; the system applies the squircle mask.
let cornerTrim = CGFloat(mascotTile.width) * 0.036
let fullBleed = makeContext(1024, 1024)
fullBleed.interpolationQuality = .high
fullBleed.draw(mascotTile.cropping(to: CGRect(x: 0, y: 0, width: mascotTile.width, height: mascotTile.height)
    .insetBy(dx: cornerTrim, dy: cornerTrim))!, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
try png(fullBleed.makeImage()!, iconDocument.appendingPathComponent("Assets/robot.png"))
try Data("""
{
  "groups" : [ { "layers" : [ { "image-name" : "robot.png", "name" : "robot" } ] } ],
  "supported-platforms" : { "squares" : "shared" }
}

""".utf8).write(to: iconDocument.appendingPathComponent("icon.json"))

let compiled = FileManager.default.temporaryDirectory.appendingPathComponent("AppIconCompiled")
try? FileManager.default.removeItem(at: compiled)
try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
let actool = Process()
actool.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
actool.arguments = ["actool", iconDocument.path, "--compile", compiled.path, "--platform", "macosx",
                    "--minimum-deployment-target", "14.0", "--app-icon", "AppIcon",
                    "--output-partial-info-plist", compiled.appendingPathComponent("partial.plist").path]
actool.standardOutput = FileHandle.nullDevice
try actool.run()
actool.waitUntilExit()
guard actool.terminationStatus == 0 else { fatalError("actool failed (needs Xcode 26+)") }
let assetsCar = packaging.appendingPathComponent("Assets.car")
try? FileManager.default.removeItem(at: assetsCar)
try FileManager.default.copyItem(at: compiled.appendingPathComponent("Assets.car"), to: assetsCar)
// (actool's own AppIcon.icns is ignored: ours keeps the flat small sizes for macOS 14–15)

// MARK: - Transparent mascot (README)

/// Alpha "choke": drops the faint halo (alpha < low) and keeps solid fur (alpha > high) untouched.
func chokeAlpha(_ image: CGImage, low: Double, high: Double) -> CGImage {
    let ctx = makeContext(image.width, image.height)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = ctx.data!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<image.height {
        for x in 0..<image.width {
            let i = y * ctx.bytesPerRow + x * 4
            let alpha = Double(pixels[i + 3])
            guard alpha > 0 else { continue }
            let newAlpha = min(max((alpha - low) / (high - low), 0), 1) * 255
            let factor = newAlpha / alpha   // premultiplied: scale color with alpha
            for c in 0..<3 { pixels[i + c] = UInt8(min(Double(pixels[i + c]) * factor, 255)) }
            pixels[i + 3] = UInt8(newAlpha)
        }
    }
    return ctx.makeImage()!
}

let mascot = chokeAlpha(loadCGImage(packaging.appendingPathComponent("source/mascot.png")), low: 90, high: 200)
let content = solidBounds(mascot, minAlpha: 0, fraction: 0)   // any visible pixel
let side = Int(max(content.width, content.height) * 1.08)      // 4% padding each side
let canvas = makeContext(512, 512)
canvas.interpolationQuality = .high
let scale = 512 / CGFloat(side)
let drawn = CGSize(width: content.width * scale, height: content.height * scale)
canvas.draw(mascot.cropping(to: content)!,
            in: CGRect(x: (512 - drawn.width) / 2, y: (512 - drawn.height) / 2, width: drawn.width, height: drawn.height))
try png(canvas.makeImage()!, packaging.appendingPathComponent("Mascot.png"))

print("Wrote AppIcon.icon, Assets.car, AppIcon.icns, AppIcon-1024.png, Mascot.png in \(packaging.path)")
