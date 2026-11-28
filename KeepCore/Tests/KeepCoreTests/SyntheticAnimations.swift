import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Made-up animations for QA #87 (ruling 2026-11-28): an APNG and a WebP of 8 x 8 pixels, built here byte by byte so
/// that the tests do not depend on what the OS can write (it can write a GIF, and WebP only on some systems).
/// The pictures of the WebP are the chunks Chromium's encoder wrote for a made-up 8 x 8 picture (two squares, no
/// one's image): the frames are real pictures, so ImageIO has to decode them, not only to find their headers.
enum Synthetic {
    // MARK: bytes

    private static func be32(_ n: Int) -> [UInt8] { [UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)] }
    private static func le(_ n: Int, _ bytes: Int) -> [UInt8] { (0..<bytes).map { UInt8((n >> (8 * $0)) & 255) } }
    private static func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }
    private static func hex(_ s: String) -> [UInt8] {
        stride(from: 0, to: s.count, by: 2).map { i in
            let a = s.index(s.startIndex, offsetBy: i)
            return UInt8(s[a..<s.index(a, offsetBy: 2)], radix: 16)!
        }
    }

    // MARK: WebP: "RIFF", the size, "WEBP", then chunks of type, length (little-endian), data, and a byte more when the data is odd

    /// The `VP8 ` (lossy) and `VP8L` (lossless) chunks of an 8 x 8 picture, as they are in a file (header and padding included).
    static let lossyPicture = hex("565038204a0000003002009d012a0800080001402625b00274ba008600056cb36a0000fefcac7d3fcc885ffecf07f2ea7ff55dcffcba6a716e7ebc7ffd741dad67c7d3ff854f863f1ffdd82ffdd82ff5b000")
    static let losslessPicture = hex("5650384c170000002f07c001000f301ef750bd15f2fc470b0eff1fd1ff800700")

    static func webpChunk(_ type: String, _ data: [UInt8]) -> [UInt8] { ascii(type) + le(data.count, 4) + data + (data.count % 2 == 1 ? [0] : []) }
    static func riff(_ chunks: [[UInt8]]) -> Data {
        let body = ascii("WEBP") + chunks.flatMap { $0 }
        return Data(ascii("RIFF") + le(body.count, 4) + body)
    }
    /// The `VP8X` header of an 8 x 8 picture. Flags: 0x02 animation, 0x04 XMP, 0x08 EXIF, 0x10 alpha, 0x20 colour profile.
    static func vp8x(_ flags: UInt8) -> [UInt8] { webpChunk("VP8X", [flags, 0, 0, 0] + le(7, 3) + le(7, 3)) }
    static func anmf(_ picture: [UInt8]) -> [UInt8] { webpChunk("ANMF", le(0, 3) + le(0, 3) + le(7, 3) + le(7, 3) + le(100, 3) + [0] + picture) }

    /// An animated WebP: the animation flag set, an `ANIM` chunk, and `frames` `ANMF` chunks.
    static func animatedWebP(frames: Int, picture: [UInt8] = lossyPicture) -> Data {
        riff([vp8x(0x02), webpChunk("ANIM", [UInt8](repeating: 0, count: 6))] + (0..<frames).map { _ in anmf(picture) })
    }
    /// A still WebP: a bare picture, or under a `VP8X` header with these flags (the animation flag is not among them).
    static func stillWebP(flags: UInt8? = nil, picture: [UInt8] = lossyPicture) -> Data {
        riff((flags.map { [vp8x($0)] } ?? []) + [picture])
    }
    /// `ANMF` chunks under a `VP8X` header that does not have the animation flag: not an animation.
    static func webPWithFramesButNoFlag(frames: Int) -> Data {
        riff([vp8x(0x10)] + (0..<frames).map { _ in anmf(lossyPicture) })
    }

    // MARK: APNG: signature, then chunks of length, type, data and the CRC of type and data

    private static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xedb88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xffffffff
        for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 255)] ^ (c >> 8) }
        return c ^ 0xffffffff
    }
    private static func pngChunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        let body = ascii(type) + data
        return be32(data.count) + body + be32(Int(crc32(body)))
    }

    /// The chunks (type, data) of a PNG file.
    private static func pngChunks(_ png: Data) -> [(String, [UInt8])] {
        let b = [UInt8](png)
        var i = 8
        var out: [(String, [UInt8])] = []
        while i + 8 <= b.count {
            let size = Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
            out.append((String(decoding: b[(i + 4)..<(i + 8)], as: UTF8.self), Array(b[(i + 8)..<(i + 8 + size)])))
            i += 12 + size
        }
        return out
    }

    /// An APNG of the 16 x 16 still picture `still` (a PNG ImageIO wrote), repeated `frames` times, whose `acTL` says
    /// `frames` (with 1 it is a still picture that carries the chunk). It is the same file a Pillow-made APNG is: an
    /// `acTL`, the first picture as the default image under an `fcTL`, then an `fcTL` and `fdAT` for each of the others.
    static func apng(frames: Int, still: Data) -> Data {
        let chunks = pngChunks(still)
        let ihdr = chunks.first { $0.0 == "IHDR" }!.1
        let idat = chunks.filter { $0.0 == "IDAT" }.flatMap { $0.1 }
        let width = Int(ihdr[0]) << 24 | Int(ihdr[1]) << 16 | Int(ihdr[2]) << 8 | Int(ihdr[3])
        let height = Int(ihdr[4]) << 24 | Int(ihdr[5]) << 16 | Int(ihdr[6]) << 8 | Int(ihdr[7])
        func fcTL(_ sequence: Int) -> [UInt8] {
            pngChunk("fcTL", be32(sequence) + be32(width) + be32(height) + be32(0) + be32(0) + [0, 10, 0, 100, 0, 0])
        }
        var parts = [pngChunk("IHDR", ihdr), pngChunk("acTL", be32(frames) + be32(0)), fcTL(0), pngChunk("IDAT", idat)]
        var sequence = 1
        for _ in 1..<max(frames, 1) {
            parts.append(fcTL(sequence)); sequence += 1
            parts.append(pngChunk("fdAT", be32(sequence) + idat)); sequence += 1
        }
        parts.append(pngChunk("IEND", []))
        return Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] + parts.flatMap { $0 })
    }

    /// The picture inside a PNG: the made-up 16 x 16 still of the tests.
    static func stillPNG() -> Data {
        let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }
}
