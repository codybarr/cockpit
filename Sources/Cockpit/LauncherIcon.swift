import AppKit

/// Normalizes workspace icons so transparent asset margins don't shrink them in result rows.
@MainActor
enum LauncherIcon {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(forFile path: String) -> NSImage {
        if let image = cache.object(forKey: path as NSString) { return image }
        let original = NSWorkspace.shared.icon(forFile: path)
        let image = trimmingTransparentMargins(original)
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    private static func trimmingTransparentMargins(_ image: NSImage) -> NSImage {
        let size = 128
        var rect = CGRect(x: 0, y: 0, width: size, height: size)
        guard let source = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return image }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let bounds: CGRect? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return nil }
            context.draw(source, in: rect)
            let bytes = buffer.bindMemory(to: UInt8.self)
            var minX = size, minY = size, maxX = -1, maxY = -1
            for y in 0..<size {
                for x in 0..<size where bytes[(y * size + x) * 4 + 3] > 16 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
        let bitmap = pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )?.makeImage()
        }
        guard let bounds, let cropped = bitmap?.cropping(to: bounds) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: bounds.width, height: bounds.height))
    }
}
