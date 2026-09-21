// Export opaque App Store PNGs without resizing or changing RGB content.
// Usage: swift release/prepare-screenshots.swift INPUT_DIRECTORY OUTPUT_DIRECTORY
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct ExportError: Error { let message: String }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ExportError(message: message) }
}
func pixels(_ image: CGImage) throws -> [UInt8] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let succeeded = data.withUnsafeMutableBytes { bytes -> Bool in
        guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return true
    }
    try require(succeeded, "Could not inspect pixels")
    return data
}
try require(CommandLine.arguments.count == 3, "Expected input and output directories")
let input = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for file in try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil).filter({ $0.pathExtension.lowercased() == "png" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
          let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let provider = original.dataProvider, let colorSpace = original.colorSpace else {
        throw ExportError(message: "Could not open \(file.lastPathComponent)")
    }
    let before = try pixels(original)
    try require(stride(from: 3, to: before.count, by: 4).allSatisfy { before[$0] == 255 }, "Source has transparent pixels")
    let alpha: CGImageAlphaInfo
    switch original.alphaInfo {
    case .last, .premultipliedLast, .noneSkipLast: alpha = .noneSkipLast
    case .first, .premultipliedFirst, .noneSkipFirst: alpha = .noneSkipFirst
    case .none: alpha = .none
    default: throw ExportError(message: "Unsupported alpha layout")
    }
    let info = CGBitmapInfo(rawValue: (original.bitmapInfo.rawValue & ~CGBitmapInfo.alphaInfoMask.rawValue) | alpha.rawValue)
    guard let opaque = CGImage(width: original.width, height: original.height,
                               bitsPerComponent: original.bitsPerComponent, bitsPerPixel: original.bitsPerPixel,
                               bytesPerRow: original.bytesPerRow, space: colorSpace, bitmapInfo: info,
                               provider: provider, decode: nil, shouldInterpolate: original.shouldInterpolate,
                               intent: original.renderingIntent) else { throw ExportError(message: "Could not remove alpha channel") }
    let target = output.appendingPathComponent(file.lastPathComponent)
    guard let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw ExportError(message: "Could not create PNG") }
    CGImageDestinationAddImage(destination, opaque, nil)
    try require(CGImageDestinationFinalize(destination), "Could not write PNG")
    guard let resultSource = CGImageSourceCreateWithURL(target as CFURL, nil),
          let result = CGImageSourceCreateImageAtIndex(resultSource, 0, nil) else { throw ExportError(message: "Could not verify PNG") }
    try require(before == pixels(result), "Pixel content changed")
    print("\(target.lastPathComponent): \(result.width)×\(result.height), identical RGB pixels, opaque PNG")
}
