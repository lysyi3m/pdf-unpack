#!/usr/bin/env swift
// Renders AppIcon-Dev from AppIcon: the same art with an amber "DEV" band across the bottom, so a
// Debug build is never mistaken for the App Store app in the Dock, Spotlight or the Home Screen.
// Run again whenever AppIcon changes.
//
// Shared word for word by every app in this family. Change all copies together.
//
// Usage: Scripts/make-dev-icon.swift

import AppKit
import CoreText

let assets = URL(filePath: CommandLine.arguments[0]).deletingLastPathComponent()
    .appending(path: "../Sources/App/Assets.xcassets").standardized
let source = assets.appending(path: "AppIcon.appiconset")
let target = assets.appending(path: "AppIcon-Dev.appiconset")

let fileManager = FileManager.default
try? fileManager.removeItem(at: target)
try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
try fileManager.copyItem(at: source.appending(path: "Contents.json"), to: target.appending(path: "Contents.json"))

for name in try fileManager.contentsOfDirectory(atPath: source.path()) where name.hasSuffix(".png") {
    guard
        let provider = CGDataProvider(url: source.appending(path: name) as CFURL),
        let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    else { fatalError("cannot read \(name)") }

    let width = image.width, height = image.height
    let size = CGFloat(height)
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("cannot draw \(name)") }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    // The bottom fifth stays inside the macOS and iOS icon masks, which only round the corners.
    let band = CGRect(x: 0, y: 0, width: CGFloat(width), height: size * 0.2)
    context.setFillColor(CGColor(srgbRed: 0.98, green: 0.72, blue: 0.0, alpha: 1))
    context.fill(band)

    let font = NSFont.systemFont(ofSize: size * 0.13, weight: .black)
    let label = NSAttributedString(string: "DEV", attributes: [
        .font: font,
        .foregroundColor: CGColor(gray: 0.05, alpha: 1),
        .kern: size * 0.02,
    ])
    let line = CTLineCreateWithAttributedString(label)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    context.textPosition = CGPoint(
        x: band.midX - bounds.width / 2 - bounds.minX,
        y: band.midY - bounds.height / 2 - bounds.minY
    )
    CTLineDraw(line, context)

    guard
        let output = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(target.appending(path: name) as CFURL, "public.png" as CFString, 1, nil)
    else { fatalError("cannot write \(name)") }
    CGImageDestinationAddImage(destination, output, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("cannot write \(name)") }
}

print("✓ \(target.path())")
