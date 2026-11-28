import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The design tokens of the spec (design/tokens.css), mirrored value for value. No colour is defined
/// anywhere else in the app. `SPEC_REF` at the root of this repository names the spec commit this file
/// mirrors; CI checks that commit out and ThemeAndStringsTests compares against it.
public enum Theme {
    public struct Token: Equatable, Sendable {
        public let light: UInt32
        public let dark: UInt32
    }

    /// Name in tokens.css (without `--ke-`) to its light and dark values.
    public static let tokens: [String: Token] = [
        "bg": Token(light: 0xF9F6F4, dark: 0x191817),
        "card": Token(light: 0xFFFDFC, dark: 0x292725),
        "quiet": Token(light: 0xEEECEC, dark: 0x383532),
        "line": Token(light: 0xD7D1CF, dark: 0x625C57),
        "text": Token(light: 0x252321, dark: 0xF6F3F0),
        "text-2": Token(light: 0x45403D, dark: 0xDDD7D2),
        "text-3": Token(light: 0x605B59, dark: 0xBDB5AF),
        "danger": Token(light: 0xB3261E, dark: 0xF2877B),
        "on-solid": Token(light: 0xFFFFFF, dark: 0x252321),
        "solid": Token(light: 0x343231, dark: 0xEFEBE7),
        "black": Token(light: 0x0B0B0B, dark: 0x0B0B0B),
        "white": Token(light: 0xFFFFFF, dark: 0xFFFFFF),
        "paper": Token(light: 0xF5F5F3, dark: 0xF5F5F3),
        "gold": Token(light: 0xC5A229, dark: 0xC5A229),
        "gold-ink": Token(light: 0x795600, dark: 0xF2D27D),
    ]

    public static let bg = color("bg")
    public static let card = color("card")
    public static let quiet = color("quiet")
    public static let line = color("line")
    public static let text = color("text")
    public static let text2 = color("text-2")
    public static let text3 = color("text-3")
    public static let danger = color("danger")
    public static let onSolid = color("on-solid")
    public static let solid = color("solid")
    public static let black = color("black")
    public static let white = color("white")
    public static let paper = color("paper")
    /// The brand accent. For what was kept (a note, a "worth a deep dive" verdict, an unread daily
    /// digest, a calendar day with a note) and for the short line above the selected tab. Never a
    /// button, link, divider or decoration, and never body text on a light background.
    public static let gold = color("gold")
    /// The darker gold for a gold WORD (the spec's "worth a deep dive" hint), which keeps the contrast
    /// that `gold` itself does not. No word in the app is set in gold yet, so nothing uses it.
    public static let goldInk = color("gold-ink")

    /// The rounding scale of tokens.css, in points. One scale for every client; which component takes
    /// which step is `Surface`, not a choice made where a view is written.
    public enum Radius {
        /// `--ke-radius-mark`: marks and logos, square.
        public static let mark: CGFloat = 0
        /// `--ke-radius-tag`.
        public static let tag: CGFloat = 8
        /// `--ke-radius`: fields and small blocks.
        public static let base: CGFloat = 14
        /// `--ke-radius-card`.
        public static let card: CGFloat = 20
        /// `--ke-radius-sheet`: the top corners of a bottom sheet.
        public static let sheet: CGFloat = 28
        /// `--ke-radius-control`: pills (buttons, chips), fully round. Drawn as a `Capsule`.
        public static let control: CGFloat = 999

        /// Name in tokens.css (without `--ke-`) to its value.
        public static let tokens: [String: CGFloat] = [
            "radius-mark": mark,
            "radius-tag": tag,
            "radius": base,
            "radius-card": card,
            "radius-sheet": sheet,
            "radius-control": control,
        ]
    }

    /// Every rounded shape in App/ and ShareExtension/, and the token it takes its rounding from. A view
    /// asks `Theme.shape(_:)` for its own entry instead of naming a radius, so this table is the one
    /// place that says which component gets which step, and ThemeAndStringsTests checks it against
    /// tokens.css and against the sources. A new rounded component adds a case here.
    public enum Surface: String, CaseIterable, Sendable {
        // Cards: `--ke-radius-card`.
        /// The `card()` modifier: a pressed-or-holding block with a fill and a border.
        case card
        /// What shows behind a row while it is swiped; it sits under a card, so it has the card's corners.
        case swipeBackground
        /// The one-line notice bar (the web's `.said`).
        case notice
        /// The card the share sheet writes its sentence on.
        case shareCard

        // Fields and small blocks: `--ke-radius`.
        /// The quiet grey block (`quietBox()`), e.g. the line to copy in the deep-dive sheet.
        case quietBox
        /// A one-line text field.
        case field
        /// A multi-line text editor.
        case textEditor
        /// The outlined field on the sign-in page, which is always dark.
        case darkField
        /// The picture of an item's original (the web's `.original-image`).
        case originalImage

        // Pills: `--ke-radius-control`, a `Capsule`.
        /// The solid button.
        case solidButton
        /// The outlined button.
        case quietButton
        /// A choice that can be switched on (the product choice).
        case choiceChip
        /// The narrow status mark that opens the status.
        case statusMark
        /// Both buttons of the share sheet.
        case shareButton

        /// Name of its token in tokens.css, without `--ke-`.
        public var token: String {
            switch self {
            case .card, .swipeBackground, .notice, .shareCard: return "radius-card"
            case .quietBox, .field, .textEditor, .darkField, .originalImage: return "radius"
            case .solidButton, .quietButton, .choiceChip, .statusMark, .shareButton: return "radius-control"
            }
        }
    }

    /// The shape of a component: a `Capsule` for a pill, otherwise a rounded rectangle of its token's radius.
    public static func shape(_ surface: Surface) -> AnyShape {
        if surface.token == "radius-control" { return AnyShape(Capsule()) }
        guard let radius = Radius.tokens[surface.token] else { fatalError("unknown radius token \(surface.token)") }
        return AnyShape(RoundedRectangle(cornerRadius: radius))
    }

    public enum Size {
        public static let display: CGFloat = 32
        public static let title: CGFloat = 26
        public static let subtitle: CGFloat = 20
        public static let item: CGFloat = 17
        public static let body: CGFloat = 16
        public static let secondary: CGFloat = 14
        public static let caption: CGFloat = 13
    }

    public static let display = Font.system(size: Size.display, weight: .bold)
    public static let title = Font.system(size: Size.title, weight: .semibold)
    public static let subtitle = Font.system(size: Size.subtitle, weight: .semibold)
    public static let item = Font.system(size: Size.item, weight: .semibold)
    public static let body = Font.system(size: Size.body)
    public static let bodyStrong = Font.system(size: Size.body, weight: .semibold)
    public static let secondary = Font.system(size: Size.secondary)
    public static let caption = Font.system(size: Size.caption)

    private static func rgb(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private static func color(_ name: String) -> Color {
        guard let t = tokens[name] else { fatalError("unknown token \(name)") }
        #if canImport(UIKit)
        return Color(UIColor { traits in
            let (r, g, b) = rgb(traits.userInterfaceStyle == .dark ? t.dark : t.light)
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
        #else
        let (r, g, b) = rgb(t.light)
        return Color(red: r, green: g, blue: b)
        #endif
    }
}
