import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import KeepCore

/// QA #87: what the share sheet says about a picture. The static line is not part of the sentence of a save;
/// the sentences of a picture that was not saved as shared say what was saved instead; "too large" and
/// "unreadable" are told apart only where the code knows which.
final class ImageNoticeTests: XCTestCase {
    private let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func text(_ key: String, _ lang: String) throws -> String {
        let url = repo.appendingPathComponent("KeepCore/Sources/KeepCore/Resources/Localizable.xcstrings")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: [String: Any]])
        let unit = ((strings[key]?["localizations"] as? [String: Any])?[lang] as? [String: Any])?["stringUnit"] as? [String: Any]
        return try XCTUnwrap(unit?["value"] as? String, "\(key) has no \(lang)")
    }

    /// A GIF (or any animated format ImageIO writes) with `frames` pictures.
    private func animation(_ type: UTType, frames: Int) -> Data {
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, frames, nil)!
        for _ in 0..<frames {
            let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    // MARK: the wording

    func testTheStaticLineAndTheSentencesAreTheDecidedWords() throws {
        XCTAssertEqual(try text("share.image_note", "zh-Hans"), "图片会压缩后存入，原图留在你的手机上。")
        XCTAssertEqual(try text("share.image_note", "en"), "Images are compressed before saving; the original stays on your phone.")
        XCTAssertEqual(try text("share.image_only_link", "zh-Hans"), "图片没能存入，只存入了链接。")
        XCTAssertEqual(try text("share.image_only_text", "zh-Hans"), "图片没能存入，只存入了文字。")
        XCTAssertEqual(try text("share.image_too_large", "zh-Hans"), "图片太大，压缩后仍超过 %lld MiB，没有存入。")
        XCTAssertEqual(try text("share.image_too_large", "en"), "This image is too large even after compression (over %lld MiB), so it wasn't saved.")
        XCTAssertEqual(try text("share.image_unreadable", "zh-Hans"), "这张图片读不出来，没有存入。")
        XCTAssertEqual(try text("share.image_failed", "zh-Hans"), "这张图片没能存入（太大或读不出来）。")
        XCTAssertEqual(try text("share.image_failed", "en"), "This image couldn't be saved (too large or unreadable).")
        // One frame, and not which one: only that one picture was kept is known.
        XCTAssertEqual(try text("share.gif_one_frame", "zh-Hans"), "动图只保留了一帧。")
        XCTAssertFalse(try text("share.gif_one_frame", "zh-Hans").contains("第一"))
        XCTAssertFalse(try text("share.gif_one_frame", "en").lowercased().contains("first"))
    }

    /// The limit is written in the unit it is in. 3,145,728 bytes (the contract's value, also the code's fallback) is 3 MiB.
    func testTheLimitIsNamedInMebibytesAndNeverAsMegabytes() throws {
        XCTAssertEqual(ImageNote.mebibytes(3_145_728), 3)
        XCTAssertEqual(ImageNote.mebibytes(Meta.bundled.limit("asset_max_bytes") ?? 0), 3)
        XCTAssertEqual(ImageNote.mebibytes(5 * 1_048_576), 5)
        // Rounded down: "over N MiB" is true of everything refused. 3,000,000 bytes is 2.86 MiB, not 3.
        XCTAssertEqual(ImageNote.mebibytes(3_000_000), 2)
        XCTAssertEqual(ImageNote.mebibytes(3_145_729), 3)
        XCTAssertEqual(ImageNote.mebibytes(0), 0)
        XCTAssertEqual(ImageNote.mebibytes(-5), 0)
        for lang in ["zh-Hans", "en"] {
            let s = try text("share.image_too_large", lang)
            XCTAssertTrue(s.contains("%lld MiB"), lang)
            XCTAssertFalse(s.contains(" MB"), lang)
        }
    }

    func testNothingPromisesWhatWasNotChecked() throws {
        for key in ["share.image_note", "share.image_only_link", "share.image_only_text", "share.image_too_large", "share.image_unreadable", "share.image_failed", "share.gif_one_frame"] {
            for lang in ["zh-Hans", "en"] {
                let s = try text(key, lang).lowercased()
                for banned in ["原图保存", "高清", "无损", "lossless", "high quality", "hd"] { XCTAssertFalse(s.contains(banned), "\(key) \(lang): \(banned)") }
            }
        }
    }

    // MARK: why a picture was not prepared

    func testAPictureThatCannotBeReadIsUnreadable() {
        XCTAssertEqual(ImagePrep.prepareDetailed(Data("not an image".utf8)), .unreadable)
        XCTAssertEqual(ImagePrep.prepareDetailed(Data()), .unreadable)
        XCTAssertNil(ImagePrep.prepare(Data("not an image".utf8)))
    }

    func testAPictureThatStaysOverTheLimitAtEveryQualityIsTooLarge() {
        XCTAssertEqual(ImagePrep.prepareDetailed(TestImage.png(width: 800, height: 600), maxBytes: 10), .tooLarge)
        XCTAssertNil(ImagePrep.prepare(TestImage.png(width: 800, height: 600), maxBytes: 10))
    }

    func testAnOrdinaryPictureIsReadyAndPrepareAgrees() throws {
        let source = TestImage.png(width: 800, height: 600)
        guard case .ready(let p) = ImagePrep.prepareDetailed(source) else { return XCTFail("not ready") }
        XCTAssertEqual(p, try XCTUnwrap(ImagePrep.prepare(source)))
    }

    // MARK: an animation

    func testAnAnimationIsCountedFromTheFileAndAStillGIFIsNot() {
        XCTAssertTrue(ImagePrep.isAnimation(animation(.gif, frames: 3)))
        XCTAssertFalse(ImagePrep.isAnimation(animation(.gif, frames: 1)), "a still GIF loses nothing")
        XCTAssertFalse(ImagePrep.isAnimation(TestImage.png(width: 40, height: 30)))
        XCTAssertFalse(ImagePrep.isAnimation(Data("not an image".utf8)))
    }

    func testAnAnimationIsPreparedAsOnePicture() throws {
        let source = animation(.gif, frames: 3)
        guard case .ready(let p) = ImagePrep.prepareDetailed(source) else { return XCTFail("not ready") }
        XCTAssertEqual(p.width, 16)
        XCTAssertTrue(ImagePrep.isAnimation(source))
    }

    // MARK: what the sentence becomes

    private let saved = SaveOutcome(kind: .saved, sentence: "Saved.")
    private let queued = SaveOutcome(kind: .queued, sentence: "Queued.")
    private let duplicate = SaveOutcome(kind: .duplicate, sentence: "Already saved.")
    private let failed = SaveOutcome(kind: .failed, sentence: "Not saved: no.")

    func testWithNothingToAddTheCoresSentenceIsUntouched() {
        for o in [saved, queued, duplicate, failed] { XCTAssertEqual(ImageNote().apply(to: o), o) }
    }

    func testAPictureSavedAsALinkSaysWhatWasSaved() {
        let note = ImageNote(instead: "The image couldn't be saved; only the link was.")
        XCTAssertEqual(note.apply(to: saved).sentence, "The image couldn't be saved; only the link was.")
        XCTAssertEqual(note.apply(to: saved).kind, .saved)
    }

    func testAQueuedSaveSaysItAfterTheQueuedSentence() {
        let note = ImageNote(instead: "The image couldn't be saved; only the text was.")
        XCTAssertEqual(note.apply(to: queued).sentence, "Queued. The image couldn't be saved; only the text was.")
        XCTAssertEqual(note.apply(to: queued).kind, .queued)
    }

    func testADuplicateAndAFailureKeepTheCoresSentence() {
        let note = ImageNote(instead: "The image couldn't be saved; only the link was.")
        XCTAssertEqual(note.apply(to: duplicate), duplicate)
        XCTAssertEqual(note.apply(to: failed), failed)
        let loss = ImageNote(after: "Only one frame of the animation was kept.")
        XCTAssertEqual(loss.apply(to: duplicate), duplicate)
        XCTAssertEqual(loss.apply(to: failed), failed)
    }

    func testALossIsSaidAfterTheCoresSentenceAndTheSaveStaysASave() {
        let note = ImageNote(after: "Only one frame of the animation was kept.")
        XCTAssertEqual(note.apply(to: saved).sentence, "Saved. Only one frame of the animation was kept.")
        XCTAssertEqual(note.apply(to: saved).kind, .saved)
        XCTAssertEqual(note.apply(to: queued).sentence, "Queued. Only one frame of the animation was kept.")
    }
}
