#!/usr/bin/env swift

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("usage: make-palette-atlas-contact-sheets.swift <input-dir> <output-dir>\n", stderr)
    exit(2)
}

let inputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let categories = [
    "Pastel", "Vintage", "Retro", "Neon", "Warm",
    "Cold", "Spring", "Summer", "Fall", "Winter",
]
let materials = [
    "Solid", "2 radial fields", "3 radial fields", "Palette wash",
    "Depth palette", "Glass", "Mist", "Luminous", "Soft sphere",
    "Chromatic edge", "Asymmetric pool", "Soft outline",
]
let files = try FileManager.default.contentsOfDirectory(
    at: inputDirectory,
    includingPropertiesForKeys: nil
)
let imageByIndex = Dictionary(uniqueKeysWithValues: files.compactMap { url -> (Int, NSImage)? in
    guard let index = Int(url.lastPathComponent.prefix(3)),
          let image = NSImage(contentsOf: url) else { return nil }
    return (index, image)
})
guard imageByIndex.count == categories.count * materials.count else {
    throw NSError(
        domain: "PaletteAtlas",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Expected 120 screenshots, found \(imageByIndex.count)"]
    )
}

let thumbnailWidth: CGFloat = 180
let thumbnailHeight: CGFloat = 390
let columnGap: CGFloat = 10
let rowGap: CGFloat = 30
let leftLabelWidth: CGFloat = 170
let topTitleHeight: CGFloat = 72
let columnLabelHeight: CGFloat = 34
let outerMargin: CGFloat = 24
let canvasWidth = outerMargin * 2 + leftLabelWidth
    + CGFloat(categories.count) * thumbnailWidth
    + CGFloat(categories.count - 1) * columnGap
let canvasHeight = outerMargin * 2 + topTitleHeight + columnLabelHeight
    + 3 * thumbnailHeight + 2 * rowGap

func appKitRect(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    NSRect(x: x, y: canvasHeight - top - height, width: width, height: height)
}

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
    .foregroundColor: NSColor.white,
]
let labelAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 17, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.86, alpha: 1),
]
let indexAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
    .foregroundColor: NSColor.white,
]

for page in 0..<4 {
    let image = NSImage(size: NSSize(width: canvasWidth, height: canvasHeight))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: image.size)).fill()

    let range = page * 3..<(page + 1) * 3
    let title = "Day Objects · app-native palette atlas · \(range.lowerBound + 1)–\(range.upperBound) of 12"
    title.draw(
        at: NSPoint(x: outerMargin, y: canvasHeight - outerMargin - 34),
        withAttributes: titleAttributes
    )

    for (column, category) in categories.enumerated() {
        let x = outerMargin + leftLabelWidth + CGFloat(column) * (thumbnailWidth + columnGap)
        let size = category.size(withAttributes: labelAttributes)
        category.draw(
            at: NSPoint(
                x: x + (thumbnailWidth - size.width) * 0.5,
                y: canvasHeight - outerMargin - topTitleHeight - 23
            ),
            withAttributes: labelAttributes
        )
    }

    for localRow in 0..<3 {
        let materialIndex = page * 3 + localRow
        let top = outerMargin + topTitleHeight + columnLabelHeight
            + CGFloat(localRow) * (thumbnailHeight + rowGap)
        let material = materials[materialIndex]
        material.draw(
            in: appKitRect(
                x: outerMargin,
                top: top + thumbnailHeight * 0.5 - 22,
                width: leftLabelWidth - 16,
                height: 44
            ),
            withAttributes: labelAttributes
        )

        for column in categories.indices {
            let index = materialIndex * categories.count + column
            let x = outerMargin + leftLabelWidth + CGFloat(column) * (thumbnailWidth + columnGap)
            let rect = appKitRect(x: x, top: top, width: thumbnailWidth, height: thumbnailHeight)
            imageByIndex[index]!.draw(in: rect)

            let badge = NSRect(x: rect.minX + 8, y: rect.maxY - 29, width: 42, height: 22)
            NSColor.black.withAlphaComponent(0.58).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 6, yRadius: 6).fill()
            String(format: "%03d", index).draw(
                at: NSPoint(x: badge.minX + 6, y: badge.minY + 3),
                withAttributes: indexAttributes
            )
        }
    }
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PaletteAtlas", code: 2)
    }
    let output = outputDirectory.appendingPathComponent(
        String(format: "contact-sheet-%02d.png", page + 1)
    )
    try png.write(to: output, options: .atomic)
    print(output.path)
}
