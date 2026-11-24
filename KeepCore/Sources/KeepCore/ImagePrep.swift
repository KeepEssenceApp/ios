import Foundation
import ImageIO
import CryptoKit
import UniformTypeIdentifiers

public struct PreparedImage: Equatable, Sendable {
    public let data: Data
    public let contentType: String
    public let sha256: String
    public let width: Int
    public let height: Int
}

public enum ImagePrep {
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether ImageIO on this system can write WebP. It can read it everywhere; writing depends on the OS.
    public static var canEncodeWebP: Bool {
        (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(UTType.webP.identifier)
    }

    /// Resizes to `longEdge` pixels at most (never up), encodes as WebP when the system can write it and
    /// as JPEG otherwise, lowering the quality until the result fits `maxBytes`, and hashes the result.
    public static func prepare(_ source: Data, longEdge: Int = 1600, maxBytes: Int = 3_145_728) -> PreparedImage? {
        guard let src = CGImageSourceCreateWithData(source as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        let (type, contentType) = canEncodeWebP ? (UTType.webP, "image/webp") : (UTType.jpeg, "image/jpeg")
        for quality in [0.82, 0.7, 0.55, 0.4, 0.25] {
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return nil }
            let data = out as Data
            if data.count <= maxBytes {
                return PreparedImage(data: data, contentType: contentType, sha256: sha256Hex(data), width: image.width, height: image.height)
            }
        }
        return nil
    }
}
