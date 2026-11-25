import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The design tokens of the spec (design/tokens.css), mirrored value for value. No colour is defined
/// anywhere else in the app.
public enum Theme {
    public struct Token: Equatable, Sendable {
        public let light: UInt32
        public let dark: UInt32
    }

    /// Name in tokens.css (without `--ke-`) to its light and dark values.
    public static let tokens: [String: Token] = [
        "bg": Token(light: 0xF5F5F3, dark: 0x0B0B0B),
        "card": Token(light: 0xFFFFFF, dark: 0x161616),
        "quiet": Token(light: 0xEAEAE7, dark: 0x1F1F1F),
        "line": Token(light: 0xDEDEDA, dark: 0x2C2C2C),
        "text": Token(light: 0x0B0B0B, dark: 0xF5F5F3),
        "text-2": Token(light: 0x4A4A4A, dark: 0xB9B9B5),
        "text-3": Token(light: 0x6B6B6B, dark: 0x929290),
        "danger": Token(light: 0xB3261E, dark: 0xF2877B),
        "on-solid": Token(light: 0xFFFFFF, dark: 0x0B0B0B),
        "solid": Token(light: 0x0B0B0B, dark: 0xF5F5F3),
        "black": Token(light: 0x0B0B0B, dark: 0x0B0B0B),
        "white": Token(light: 0xFFFFFF, dark: 0xFFFFFF),
        "paper": Token(light: 0xF5F5F3, dark: 0xF5F5F3),
        "gold": Token(light: 0xC5A229, dark: 0xC5A229),
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

    public enum Radius {
        public static let mark: CGFloat = 0
        public static let tag: CGFloat = 4
        public static let base: CGFloat = 6
        public static let sheet: CGFloat = 10
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
