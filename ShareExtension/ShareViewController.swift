import UIKit
import SwiftUI
import UniformTypeIdentifiers
import KeepCore

/// Share › KeepEssence. One action: the content is saved without opening the app, the core's one
/// sentence is shown in a small sheet, and the sheet closes itself. The only question it ever asks
/// is about content that looks like a password or a credential.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareSheetView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        model.close = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task { await model.run(items) }
    }

    /// Ask the system for a small sheet. Where the system does not honour it for an extension, the
    /// sheet stays page-sized and the card sits at its bottom (docs/pitfalls.md).
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        preferredContentSize = CGSize(width: view.bounds.width, height: 160)
        if let sheet = sheetPresentationController ?? parent?.sheetPresentationController {
            sheet.detents = [.custom { _ in 160 }]
            sheet.prefersGrabberVisible = false
            sheet.preferredCornerRadius = Theme.Radius.sheet
        }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum Phase: Equatable {
        case working
        case asking(String)
        case said(SaveOutcome.Kind?, String)
    }

    @Published var phase: Phase = .working
    /// A second, smaller line under the sentence: what to do next.
    @Published var hint: String?
    /// A picture was shared: the static line under the card says what happens to it (QA #87).
    @Published var hasImage = false
    /// What the picture's sentence adds to the core's, when what was saved is not the picture as shared.
    private var imageNote = ImageNote()
    var close: () -> Void = {}
    private var draft: SaveDraft?
    private let store = KeepStore.shared
    private var closed = false

    /// The picture was not saved, and the link or the text that came with it was: said as done, and as will-be while it waits.
    private func instead(for shared: Shared) -> ImageNote {
        if shared.url != nil { return ImageNote(instead: L("share.image_only_link"), queuedInstead: L("share.image_only_link_queued")) }
        return ImageNote(instead: L("share.image_only_text"), queuedInstead: L("share.image_only_text_queued"))
    }

    func run(_ items: [NSExtensionItem]) async {
        guard let shared = await Shared.read(items) else {
            return finish(.failed, failedSentence(L("share.nothing")), after: 3)
        }
        let meta = store.meta
        var image: PreparedImage?
        if let data = shared.imageData {
            hasImage = true
            // The same two values prepare the picture and are named in the sentence about it.
            let maxBytes = meta.limit("asset_max_bytes") ?? 3_145_728
            switch ImagePrep.prepareDetailed(data, longEdge: meta.limit("image_long_edge_px") ?? 1600, maxBytes: maxBytes) {
            case .ready(let prepared):
                image = prepared
                if ImagePrep.isAnimation(data) { imageNote = ImageNote(after: L("share.gif_one_frame")) }
            case .tooLarge:
                if shared.url == nil && shared.text == nil { return finish(.failed, L("share.image_too_large", ImageNote.mebibytes(maxBytes)), after: 3.2) }
                imageNote = instead(for: shared)
            case .unreadable:
                if shared.url == nil && shared.text == nil { return finish(.failed, L("share.image_unreadable"), after: 3.2) }
                imageNote = instead(for: shared)
            case .failed:
                // The encoder failed: that is neither "too large" nor "unreadable", so it is not said to be.
                if shared.url == nil && shared.text == nil { return finish(.failed, L("share.image_failed"), after: 3.2) }
                imageNote = instead(for: shared)
            }
        }
        let request: SaveRequest
        if image != nil {
            request = SaveRequest(kind: "image", url: shared.url, title: shared.title, text: shared.text, entry: "share")
        } else if let url = shared.url {
            request = SaveRequest(kind: "link", url: url, title: shared.title, text: shared.text, entry: "share")
        } else {
            request = SaveRequest(kind: "text", title: shared.title, text: shared.text, entry: "share")
        }
        draft = SaveDraft(request: request, image: image)

        // Rule B4: content that looks like a password is neither sent nor dropped silently.
        let matcher = SecretMatcher(rules: meta.sharedRules)
        if matcher.looksSecret(shared.text) || matcher.looksSecret(shared.url) {
            phase = .asking(meta.sharedRules.saveMessage("secret_like_question", lang: KeepLang.current) ?? "")
            return
        }
        await send()
    }

    func answer(save: Bool) {
        guard save else { return finish(nil, service.declinedSentence, after: 1.6) }
        phase = .working
        Task { await send() }
    }

    private func failedSentence(_ reason: String) -> String {
        store.meta.sharedRules.saveMessage("failed", lang: KeepLang.current, reason: reason) ?? reason
    }

    private var service: SaveService {
        SaveService(client: store.makeClient(), queue: store.queue, rules: store.meta.sharedRules)
    }

    private func send() async {
        guard let draft else { return }
        guard store.credential != nil else {
            // Nothing can be sent before signing in, and only the app can do that: the save waits on
            // the device, and the sheet says so and what to do.
            let held = imageNote.apply(to: service.hold(draft))
            hint = held.kind == .queued ? L("share.sign_in_first") : nil
            return finish(held.kind, held.sentence, after: 4)
        }
        let outcome = imageNote.apply(to: await service.save(draft))
        finish(outcome.kind, outcome.sentence, after: outcome.kind == .failed || outcome.kind == .queued ? 3.2 : 2.2)
    }

    private func finish(_ kind: SaveOutcome.Kind?, _ sentence: String, after seconds: Double) {
        phase = .said(kind, sentence)
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            finishNow()
        }
    }

    func finishNow() {
        guard !closed else { return }
        closed = true
        close()
    }
}

/// What the host app handed over: at most one web address, some text, one image.
struct Shared {
    var url: String?
    var title: String?
    var text: String?
    var imageData: Data?

    static func read(_ items: [NSExtensionItem]) async -> Shared? {
        var out = Shared()
        for item in items {
            for provider in item.attachments ?? [] {
                if out.imageData == nil, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    out.imageData = await image(provider)
                } else if out.url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let u = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, isWeb(u) {
                        out.url = u.absoluteString
                    }
                } else if out.text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let s = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                        out.text = s
                    }
                }
            }
            if out.title == nil {
                let t = item.attributedTitle?.string ?? item.attributedContentText?.string
                if let t, !t.isEmpty, t.count <= 300 { out.title = t }
            }
        }
        // Text that is nothing but a web address is a link.
        if out.url == nil, let t = out.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !t.contains(where: \.isWhitespace), let u = URL(string: t), isWeb(u) {
            out.url = t
            out.text = nil
        }
        if out.title == out.url || out.title == out.text { out.title = nil }
        if let t = out.text, t.count > 200_000 { out.text = String(t.prefix(200_000)) }
        if let u = out.url, u.count > 2000 { out.url = nil; out.text = out.text ?? u }
        guard out.url != nil || out.imageData != nil || !(out.text ?? "").isEmpty else { return nil }
        return out
    }

    private static func isWeb(_ u: URL) -> Bool { ["http", "https"].contains(u.scheme?.lowercased() ?? "") }

    private static func image(_ provider: NSItemProvider) async -> Data? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) else { return nil }
        if let url = item as? URL { return try? Data(contentsOf: url) }
        if let data = item as? Data { return data }
        if let image = item as? UIImage { return image.pngData() }
        return nil
    }
}

struct ShareSheetView: View {
    @ObservedObject var model: ShareModel
    @Environment(\.colorScheme) private var scheme

    private var isAsking: Bool {
        if case .asking = model.phase { return true }
        return false
    }

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Image(scheme == .dark ? "MarkOnDark" : "MarkOnLight")
                        .resizable().scaledToFit().frame(height: 28)
                        .accessibilityHidden(true)
                    content
                    Spacer(minLength: 0)
                }
                // What happens to a picture, said once under the sentence: not part of it, and not a question (QA #87).
                if model.hasImage, !isAsking {
                    Text(L("share.image_note"))
                        .font(Theme.secondary).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("share.image_note")
                }
                if case .asking = model.phase {
                    HStack(spacing: 8) {
                        Button(L("action.save")) { model.answer(save: true) }
                            .buttonStyle(ShareButton(solid: true))
                            .accessibilityIdentifier("share.save")
                        Button(L("share.dont_save")) { model.answer(save: false) }
                            .buttonStyle(ShareButton(solid: false))
                            .accessibilityIdentifier("share.dont_save")
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(Theme.shape(.shareCard))
            .overlay(Theme.shape(.shareCard).stroke(Theme.line, lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.top, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if case .said = model.phase { model.finishNow() }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .working:
            ProgressView().tint(Theme.text3)
        case .asking(let question):
            Text(question).font(Theme.bodyStrong).foregroundStyle(Theme.text)
        case .said(let kind, let sentence):
            VStack(alignment: .leading, spacing: 4) {
                Text(sentence)
                    .font(Theme.bodyStrong)
                    .foregroundStyle(kind == .failed ? Theme.danger : Theme.text)
                    .accessibilityIdentifier("share.sentence")
                if let hint = model.hint {
                    Text(hint).font(Theme.secondary).foregroundStyle(Theme.text2).accessibilityIdentifier("share.hint")
                }
            }
        }
    }
}

private struct ShareButton: ButtonStyle {
    let solid: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodyStrong)
            .foregroundStyle(solid ? Theme.onSolid : Theme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(solid ? Theme.solid : Theme.card)
            .clipShape(Theme.shape(.shareButton))
            .overlay(Theme.shape(.shareButton).stroke(solid ? Theme.solid : Theme.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
