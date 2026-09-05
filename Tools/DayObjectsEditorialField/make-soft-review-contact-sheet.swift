#!/usr/bin/env swift

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("usage: make-soft-review-contact-sheet.swift <input-dir> <output.png>\n", stderr)
    exit(2)
}

let inputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: arguments[2])
let files = try FileManager.default.contentsOfDirectory(
    at: inputDirectory,
    includingPropertiesForKeys: nil
).filter { $0.pathExtension.lowercased() == "png" }.sorted {
    $0.lastPathComponent < $1.lastPathComponent
}
guard files.count == 12 else {
    throw NSError(
        domain: "SoftReviewContactSheet",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Expected 12 screenshots, found \(files.count)"]
    )
}

let materials = [
    "Solid", "Translucent solid", "Soft mist",
    "Wide gradient", "Soft outline", "Hairline outline",
]
let placements = ["Depth field", "Equal medium"]
let thumbnailWidth: CGFloat = 280
let thumbnailHeight: CGFloat = 609
let columnGap: CGFloat = 16
let rowGap: CGFloat = 42
let labelHeight: CGFloat = 56
let titleHeight: CGFloat = 86
let margin: CGFloat = 28
let columns = 6
let rows = 2
let canvasWidth = margin * 2 + CGFloat(columns) * thumbnailWidth
    + CGFloat(columns - 1) * columnGap
let canvasHeight = margin * 2 + titleHeight
    + CGFloat(rows) * (labelHeight + thumbnailHeight)
    + CGFloat(rows - 1) * rowGap

func rectFromTop(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    NSRect(x: x, y: canvasHeight - y - height, width: width, height: height)
}

let output = NSImage(size: NSSize(width: canvasWidth, height: canvasHeight))
output.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
NSColor(calibratedWhite: 0.035, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: output.size)).fill()

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
    .foregroundColor: NSColor.white,
]
let materialAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1),
]
let placementAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 0.68, alpha: 1),
]

"Day Objects · soft material review · 2 placement modes".draw(
    at: NSPoint(x: margin, y: canvasHeight - margin - 38),
    withAttributes: titleAttributes
)

for materialIndex in materials.indices {
    let blockRow = materialIndex / 3
    let blockColumn = materialIndex % 3
    for placementIndex in placements.indices {
        let index = materialIndex * 2 + placementIndex
        let column = blockColumn * 2 + placementIndex
        let x = margin + CGFloat(column) * (thumbnailWidth + columnGap)
        let top = margin + titleHeight
            + CGFloat(blockRow) * (labelHeight + thumbnailHeight + rowGap)
        materials[materialIndex].draw(
            at: NSPoint(x: x, y: canvasHeight - top - 22),
            withAttributes: materialAttributes
        )
        placements[placementIndex].draw(
            at: NSPoint(x: x, y: canvasHeight - top - 45),
            withAttributes: placementAttributes
        )
        guard let screenshot = NSImage(contentsOf: files[index]) else {
            throw NSError(domain: "SoftReviewContactSheet", code: 2)
        }
        screenshot.draw(
            in: rectFromTop(
                x: x,
                y: top + labelHeight,
                width: thumbnailWidth,
                height: thumbnailHeight
            )
        )
    }
}
output.unlockFocus()

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
guard let tiff = output.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "SoftReviewContactSheet", code: 3)
}
try png.write(to: outputURL, options: .atomic)
print(outputURL.path)
