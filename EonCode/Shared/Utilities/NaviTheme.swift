import SwiftUI

// MARK: - NaviTheme
// Centralised design tokens. Inspired by Claude's clean, minimal aesthetic.
// Use these instead of hard-coded values throughout the app.

enum NaviTheme {

    // MARK: - Accent

    /// Primary accent — deep blue-purple (Claude-inspired)
    static let accent = Color.accentNavi  // defined in Extensions.swift

    // MARK: - Surfaces (cross-platform)

    /// Primary window/view background
    static var surface: Color { Color.chatBackground }

    /// Secondary panel background (sidebars, popovers)
    static var surfaceSecondary: Color { Color.sidebarBackground }

    /// Tertiary surface (cards, input fields)
    static var surfaceTertiary: Color {
        #if os(macOS)
        Color(NSColor.quaternaryLabelColor).opacity(0.2)
        #else
        Color(UIColor.tertiarySystemBackground)
        #endif
    }

    // MARK: - Text

    static var textPrimary: Color { .primary }
    static var textSecondary: Color { .secondary }
    static var textMuted: Color { Color.secondary.opacity(0.55) }

    // MARK: - Chat bubbles

    /// User message bubble
    static var userBubble: Color { Color.userBubble }

    /// Assistant: no background (text-only, left-aligned)
    static var assistantBubble: Color { .clear }

    // MARK: - Code blocks

    /// Dark code block background (#1C1C1E-ish, always dark regardless of theme)
    static let codeBG = Color(red: 0.11, green: 0.11, blue: 0.12)

    /// Code block border
    static let codeBorder = Color.white.opacity(0.06)

    // MARK: - Typography

    /// Body text: SF Rounded for warmth
    static func body() -> Font {
        .system(size: 15, weight: .regular, design: .rounded)
    }

    /// Small caption
    static func caption() -> Font {
        .system(size: 12, weight: .regular)
    }

    /// Monospace code font
    static func mono(size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }

    // MARK: - Radii

    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 18

    // MARK: - Spacing

    static let messagePaddingH: CGFloat = 16
    static let messagePaddingV: CGFloat = 8
    static let messageSpacing: CGFloat = 6
    static let sidebarItemPaddingH: CGFloat = 12
    static let sidebarItemPaddingV: CGFloat = 7
}
