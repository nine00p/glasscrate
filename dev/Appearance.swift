// Glass Crate — APPEARANCE ADD-ON
// Themes, title bars, text sizes, and Interface Size. Chosen in Settings → General.
//
// Themes come in two rows:
//   Glass Crate: Light, Crimson, Dark, Blackout. Glass Crate's own colors, in the red of the app icon.
//             EDIT THEM IN `GlassCrateTheme` BELOW.
//   System:   Match System, Light, Dark. The Mac's own look, with your Mac's accent color.
// Every window (main, Download Queue, Settings, About, What's New) uses the same colors,
// and every window has a solid title bar that looks the same whether it's active or not.

import SwiftUI
import AppKit

enum Appearance {
    /// Where the choice is remembered
    static let key = "appearance"
    /// What a new user starts with
    static let defaultMode = "dark"

    /// The top row in Settings → General
    static let glassCrateChoices: [(tag: String, title: String)] = [
        ("gc-light", "Light"),
        ("gc-crimson", "Crimson"),
        ("gc-dark", "Dark"),
        ("gc-blackout", "Blackout"),
    ]
    /// The bottom row
    static let systemChoices: [(tag: String, title: String)] = [
        ("system", "Match System"),
        ("light", "Light"),
        ("dark", "Dark"),
    ]

    /// The current choice
    static var mode: String { UserDefaults.standard.string(forKey: key) ?? defaultMode }
    /// The Glass Crate theme in use, or nil for a System theme
    static var theme: GlassCrateTheme? { GlassCrateTheme.all[mode] }

    /// Applies the choice to every window in the app, including About, Settings, and alerts.
    /// "Match System" follows the Mac's own setting, and changes along with it.
    static func apply(_ choice: String) {
        let m = choice
        let look: NSAppearance?
        if let t = GlassCrateTheme.all[m] {
            look = NSAppearance(named: t.isDark ? .darkAqua : .aqua)
        } else {
            switch m {
            case "light": look = NSAppearance(named: .aqua)
            case "dark":  look = NSAppearance(named: .darkAqua)
            default:      look = nil
            }
        }
        NSApp.appearance = look
        // Every open window, so Settings, About, and What's New switch right away too
        for w in NSApp.windows {
            w.appearance = look
            if !(w is NSPanel) { w.backgroundColor = .gcTitlebar }
            w.contentView?.needsDisplay = true
        }
    }
}

// MARK: - Glass Crate themes: the colors
// Change these to try different colors. Each is red, green, blue from 0 to 255.
// All the highlights come from the app icon's red (#AB0116 at the top of the icon, #830506 at the bottom).
// Dark themes use a slightly brighter red of the same color, so lit-up icons stand out on dark backgrounds.

struct GlassCrateTheme {
    let isDark: Bool
    /// Lit-up icons, Add to Crate buttons, the progress bar, the selected Settings tab, "Update available"
    let accent: NSColor
    /// The window background
    let background: NSColor
    /// The title bar across the top of every window
    let titlebar: NSColor

    /// The icon's red, and a slightly brighter version of it for dark backgrounds
    static let iconRed   = rgb(171, 1, 22)     // #AB0116
    static let brightRed = rgb(204, 18, 42)    // #CC122A

    static let all: [String: GlassCrateTheme] = [
        // Light: warm white, with the icon's red
        "gc-light": GlassCrateTheme(isDark: false,
                                  accent: iconRed,
                                  background: rgb(250, 247, 247),
                                  titlebar: rgb(236, 229, 230)),
        // Crimson: deep red everywhere (like the icon, darker), with a soft light-red highlight
        "gc-crimson": GlassCrateTheme(isDark: true,
                                    accent: rgb(255, 128, 138),
                                    background: rgb(64, 10, 16),
                                    titlebar: rgb(44, 6, 10)),
        // Dark: charcoal grey, with red highlights
        "gc-dark": GlassCrateTheme(isDark: true,
                                 accent: brightRed,
                                 background: rgb(32, 31, 32),
                                 titlebar: rgb(44, 43, 44)),
        // Blackout: nearly black, with red highlights
        "gc-blackout": GlassCrateTheme(isDark: true,
                                     accent: brightRed,
                                     background: rgb(18, 16, 17),
                                     titlebar: rgb(38, 37, 38)),
    ]

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
}

// MARK: - Interface Size
// Settings → General → Interface Size scales everything: text, icons, the browser, and the windows.

enum UIScale {
    static let key = "uiScale"
    /// 70% to 130%, in 5% steps (130% is about as wide as a laptop screen allows)
    static let choices: [(value: Double, title: String)] = stride(from: 70, through: 130, by: 5).map {
        (Double($0) / 100, "\($0)%")
    }
    static var value: Double {
        let v = UserDefaults.standard.double(forKey: key)
        return v == 0 ? 1.0 : v
    }
    /// A size scaled to the current Interface Size
    static func s(_ x: CGFloat) -> CGFloat { (x * CGFloat(value)).rounded() }
    /// Buttons and checkboxes get smaller or larger too
    static var controlSize: ControlSize { value < 0.9 ? .small : (value > 1.05 ? .large : .regular) }
}

// MARK: - Text sizes
// Every window uses these, so the whole app's text size can be adjusted right here.
// (macOS's standard sizes are about 2 points smaller; these are a step up for easier reading.)
// They follow Interface Size.

extension Font {
    static var gcTitle:    Font { .system(size: UIScale.s(20), weight: .bold) }      // window titles ("Settings")
    static var gcHeadline: Font { .system(size: UIScale.s(15), weight: .semibold) }  // section headings
    static var gcBody:     Font { .system(size: UIScale.s(15)) }                     // regular text, checkboxes, buttons
    static var gcCallout:  Font { .system(size: UIScale.s(14)) }                     // grey descriptions, status
    static var gcCaption:  Font { .system(size: UIScale.s(12)) }                     // small notes

    // The main window's controls (right side): the same sizes as everywhere else, so the
    // main window matches Settings. (They were 2 points larger for a while; Interface Size covers that now.)
    static var gcMainTitle:    Font { gcTitle }
    static var gcMainHeadline: Font { gcHeadline }
    static var gcMainBody:     Font { gcBody }
    static var gcMainCallout:  Font { gcCallout }
    static var gcMainCaption:  Font { gcCaption }
    /// Header icons (globe, pin, queue, gear)
    static var gcIcon:         Font { .system(size: UIScale.s(18)) }
}

// MARK: - Window look: solid title bar and background

extension View {
    /// The app's window look: a solid title bar (it doesn't change when the window is active or not)
    /// over the theme's background. Used by the main window, Settings, About, and What's New.
    func glassCrateChrome() -> some View {
        self.background(
            VStack(spacing: 0) {
                Color.gcTitlebar.frame(height: 28)   // the standard title bar height
                Color.gcBackground
            }
            .ignoresSafeArea()
        )
    }
}

// MARK: - Hover labels

/// Glass Crate's own tooltip: hold the mouse over an icon for a moment and a small label
/// appears just below it, in readable-size text. (The Mac's built-in tooltips didn't show up
/// for the header icons.) The label lines up with the icon's right edge so it stays inside the window.
struct HoverTip: ViewModifier {
    let text: String
    @State private var hovering = false
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hovering = inside
                if inside {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        if hovering { withAnimation(.easeOut(duration: 0.15)) { shown = true } }
                    }
                } else {
                    shown = false
                }
            }
            .overlay(alignment: .topTrailing) {
                if shown {
                    Text(text)
                        .font(.gcCaption)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                        .offset(y: 30)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
    }
}

extension View {
    /// A hover label (see HoverTip). VoiceOver reads the same text.
    func hoverTip(_ text: String) -> some View {
        modifier(HoverTip(text: text)).accessibilityLabel(text)
    }
}

// MARK: - Colors

extension Color {
    /// The app's background, from the theme
    static var gcBackground: Color { Color(nsColor: .gcBackground) }
    /// The app's highlight color: the Glass Crate theme's accent, or the Mac's accent color in System themes
    /// (Views that use it also watch the theme setting, so they update the moment it changes.)
    static var gcAccent: Color { Color(nsColor: .gcAccent) }
    /// The solid title bar color
    static var gcTitlebar: Color { Color(nsColor: .gcTitlebar) }
}

extension NSWindow {
    /// Sets a window up for the app's look: the content runs under a clear title bar, and
    /// glassCrateChrome() paints a solid bar there, so it looks the same whether the window is active or not.
    func useGlassCrateBackground() {
        styleMask.insert(.fullSizeContentView)
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        backgroundColor = .gcTitlebar
        appearance = NSApp.appearance
    }
}

extension NSColor {
    static var gcBackground: NSColor { Appearance.theme?.background ?? .textBackgroundColor }
    static var gcAccent: NSColor { Appearance.theme?.accent ?? .controlAccentColor }
    /// System themes: light grey in Light, dark grey in Dark (follows the Mac in Match System)
    static var gcTitlebar: NSColor {
        Appearance.theme?.titlebar ?? NSColor(name: nil) { look in
            look.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 42 / 255, green: 42 / 255, blue: 45 / 255, alpha: 1)
                : NSColor(srgbRed: 229 / 255, green: 229 / 255, blue: 232 / 255, alpha: 1)
        }
    }
}
