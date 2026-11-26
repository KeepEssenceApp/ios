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

    /// How a picture was (not) prepared. Only what is known for certain is told apart: the bytes could not be
    /// read as a picture (`unreadable`), or every quality that was tried is still over the limit (`tooLarge`).
    /// A failure of the encoder itself is neither of those, and is `failed` (QA #87).
    public enum Result: Equatable, Sendable {
        case ready(PreparedImage)
        case tooLarge
        case unreadable
        case failed
    }

    /// Resizes to `longEdge` pixels at most (never up), encodes as WebP when the system can write it and
    /// as JPEG otherwise, lowering the quality until the result fits `maxBytes`, and hashes the result.
    public static func prepare(_ source: Data, longEdge: Int = 1600, maxBytes: Int = 3_145_728) -> PreparedImage? {
        if case .ready(let image) = prepareDetailed(source, longEdge: longEdge, maxBytes: maxBytes) { return image }
        return nil
    }

    /// `prepare`, saying why when there is no picture.
    public static func prepareDetailed(_ source: Data, longEdge: Int = 1600, maxBytes: Int = 3_145_728) -> Result {
        guard let src = CGImageSourceCreateWithData(source as CFData, nil) else { return .unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return .unreadable }
        let (type, contentType) = canEncodeWebP ? (UTType.webP, "image/webp") : (UTType.jpeg, "image/jpeg")
        for quality in [0.82, 0.7, 0.55, 0.4, 0.25] {
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return .failed }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return .failed }
            let data = out as Data
            if data.count <= maxBytes {
                return .ready(PreparedImage(data: data, contentType: contentType, sha256: sha256Hex(data), width: image.width, height: image.height))
            }
        }
        return .tooLarge
    }

    /// Whether the source is an animation (a GIF or a PNG with more than one picture), of which `prepare` keeps one
    /// still picture. Counted from the file, not guessed from its type: a still GIF loses nothing. Which picture is
    /// kept is not claimed here (QA #87).
    public static func isAnimation(_ source: Data) -> Bool {
        guard let src = CGImageSourceCreateWithData(source as CFData, nil), let type = CGImageSourceGetType(src) as String? else { return false }
        return [UTType.gif.identifier, UTType.png.identifier].contains(type) && CGImageSourceGetCount(src) > 1
    }
}
