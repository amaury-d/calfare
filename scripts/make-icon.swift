// Renders Calflare's logo: App/Resources/AppIcon.icns and App/Resources/StatusIcon.pdf.
//
//   make icon        (compiles and runs this script)
//
// The logo is a white geometric "C" whose opening holds two sparkles, on the same
// purple-to-orange gradient as the full-screen alert (Sources/CalflareOverlay/main.swift).
import AppKit
import Foundation

let gradientStart = NSColor(srgbRed: 0.30, green: 0.05, blue: 0.55, alpha: 1)  // #4D0D8C
let gradientEnd = NSColor(srgbRed: 0.95, green: 0.38, blue: 0.10, alpha: 1)    // #F26119
let openingHalfAngle: CGFloat = 45  // degrees, centered on the right-hand side

/// A four-pointed star with concave sides.
func sparkle(center: CGPoint, radius: CGFloat) -> NSBezierPath {
    let pinch = radius * 0.16
    let path = NSBezierPath()
    path.move(to: CGPoint(x: center.x, y: center.y + radius))
    let tips = [
        (CGPoint(x: center.x + radius, y: center.y), CGPoint(x: center.x + pinch, y: center.y + pinch)),
        (CGPoint(x: center.x, y: center.y - radius), CGPoint(x: center.x + pinch, y: center.y - pinch)),
        (CGPoint(x: center.x - radius, y: center.y), CGPoint(x: center.x - pinch, y: center.y - pinch)),
        (CGPoint(x: center.x, y: center.y + radius), CGPoint(x: center.x - pinch, y: center.y + pinch))
    ]
    for (tip, control) in tips {
        path.curve(to: tip, controlPoint1: control, controlPoint2: control)
    }
    path.close()
    return path
}

/// The "C": a thick arc, open to the right, with butt caps.
func monogram(center: CGPoint, radius: CGFloat, width: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.appendArc(
        withCenter: center, radius: radius,
        startAngle: openingHalfAngle, endAngle: 360 - openingHalfAngle, clockwise: false
    )
    path.lineWidth = width
    path.lineCapStyle = .butt
    return path
}

/// Draws the logo into the current graphics context, `side` points wide.
func drawAppIcon(side: CGFloat) {
    let simplified = side <= 32  // sparkles turn to mud at tiny sizes
    let inset = side * 0.1
    let body = NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let shape = NSBezierPath(
        roundedRect: body, xRadius: body.width * 0.2237, yRadius: body.width * 0.2237
    )

    if side >= 128 {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
        shadow.shadowBlurRadius = side * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -side * 0.012)
        shadow.set()
        gradientStart.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGradient(starting: gradientStart, ending: gradientEnd)?.draw(in: shape, angle: -45)

    let center = CGPoint(x: body.midX, y: body.midY)
    let radius = body.width * (simplified ? 0.29 : 0.285)
    let width = body.width * (simplified ? 0.21 : 0.17)
    NSColor.white.setStroke()
    monogram(center: center, radius: radius, width: width).stroke()

    guard !simplified else { return }
    NSColor.white.setFill()
    sparkle(
        center: CGPoint(x: center.x + radius * 1.02, y: center.y + body.width * 0.07),
        radius: body.width * 0.115
    ).fill()
    sparkle(
        center: CGPoint(x: center.x + radius * 1.12, y: center.y - body.width * 0.115),
        radius: body.width * 0.055
    ).fill()
}

func renderPNG(pixels: Int, to url: URL) throws {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: representation) else {
        fatalError("Cannot create a bitmap context for \(pixels) px")
    }
    representation.size = NSSize(width: pixels, height: pixels)  // 1 point == 1 pixel
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    drawAppIcon(side: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = representation.representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode \(pixels) px PNG")
    }
    try data.write(to: url)
}

/// Monochrome vector glyph for the menu bar. The app loads it as a template image.
func writeStatusIcon(to url: URL) {
    var box = CGRect(x: 0, y: 0, width: 18, height: 18)
    guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
        fatalError("Cannot create a PDF context at \(url.path)")
    }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSColor.black.setStroke()
    NSColor.black.setFill()
    monogram(center: CGPoint(x: 8.2, y: 9), radius: 5.2, width: 2.5).stroke()
    sparkle(center: CGPoint(x: 13.9, y: 9), radius: 2.6).fill()
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
}

// MARK: - Main

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon <repository-root>\n".utf8))
    exit(2)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let resources = root.appendingPathComponent("App/Resources")
let workDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("calflare-icon-\(UUID().uuidString)")
let iconset = workDirectory.appendingPathComponent("AppIcon.iconset")
defer { try? FileManager.default.removeItem(at: workDirectory) }

do {
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            try renderPNG(pixels: points * scale, to: iconset.appendingPathComponent(name))
        }
    }
    let icns = resources.appendingPathComponent("AppIcon.icns")
    let converter = Process()
    converter.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    converter.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
    try converter.run()
    converter.waitUntilExit()
    guard converter.terminationStatus == 0 else {
        FileHandle.standardError.write(Data("iconutil failed\n".utf8))
        exit(1)
    }
    writeStatusIcon(to: resources.appendingPathComponent("StatusIcon.pdf"))

    // A PNG for the README: GitHub cannot render .icns.
    let docs = root.appendingPathComponent("docs")
    try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
    try renderPNG(pixels: 512, to: docs.appendingPathComponent("icon.png"))

    print("Wrote \(icns.path), StatusIcon.pdf and docs/icon.png")
} catch {
    FileHandle.standardError.write(Data("make-icon: \(error)\n".utf8))
    exit(1)
}
