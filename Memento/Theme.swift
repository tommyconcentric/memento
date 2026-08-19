import SwiftUI
import UIKit

/// Memento's palette, a Greek island summer in Mamma Mia style:
/// Aegean water, whitewashed walls, bougainvillea, taverna pots and sun.
enum Theme {
    static let aegean = Color(red: 0.118, green: 0.431, blue: 0.624)        // #1E6E9F
    static let sky = Color(red: 0.310, green: 0.651, blue: 0.835)           // #4FA6D5
    static let bougainvillea = Color(red: 0.851, green: 0.310, blue: 0.557) // #D94F8E
    static let sunshine = Color(red: 0.949, green: 0.757, blue: 0.306)      // #F2C14E
    static let olive = Color(red: 0.478, green: 0.545, blue: 0.310)         // #7A8B4F
    static let terracotta = Color(red: 0.788, green: 0.435, blue: 0.290)    // #C96F4A
    static let gold = Color(red: 0.753, green: 0.541, blue: 0.176)          // #C08A2D
    static let bark = Color(red: 0.478, green: 0.333, blue: 0.224)          // #7A5539 (tree trunks)

    // Business workspace: boardroom slate in place of holiday blues.
    static let graphite = Color(red: 0.239, green: 0.290, blue: 0.361)      // #3D4A5C
    static let steel = Color(red: 0.475, green: 0.565, blue: 0.663)         // #7990A9

    /// Warm whitewash by day, deep night sea in dark mode.
    static let background = dynamic(
        light: UIColor(red: 0.980, green: 0.965, blue: 0.937, alpha: 1),    // #FAF6EF
        dark: UIColor(red: 0.051, green: 0.106, blue: 0.149, alpha: 1)      // #0D1B26
    )

    /// Card surfaces that sit on the background.
    static let card = dynamic(
        light: .white,
        dark: UIColor(red: 0.082, green: 0.161, blue: 0.227, alpha: 1)      // #15293A
    )

    /// Business workspace surfaces: the holiday whitewash swaps for a cool
    /// boardroom slate so the two modes read differently at a glance.
    static let businessBackground = dynamic(
        light: UIColor(red: 0.949, green: 0.957, blue: 0.965, alpha: 1),    // #F2F4F6
        dark: UIColor(red: 0.055, green: 0.078, blue: 0.106, alpha: 1)      // #0E141B
    )

    static let businessCard = dynamic(
        light: .white,
        dark: UIColor(red: 0.106, green: 0.137, blue: 0.176, alpha: 1)      // #1B232D
    )

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

// MARK: - Workspace (Memento Personal vs Memento Business)

/// Two side-by-side contact books in one app: friends and family in
/// Personal, networking/business contacts in Business. The active
/// workspace filters the people list and tags newly created people.
enum Workspace: String, CaseIterable {
    case personal
    case business

    static let storageKey = "workspaceMode"

    var title: String { self == .personal ? "Personal" : "Business" }
    var icon: String { self == .personal ? "person.2" : "briefcase" }
    var accent: Color { self == .personal ? Theme.aegean : Theme.graphite }

    /// Personal keeps the warm serif voice; Business drops to the system
    /// sans for a plainer, corporate register. Every view that renders
    /// display text (names, tab labels, empty states) should pick its
    /// design through this rather than hardcoding `.serif`.
    var displayFontDesign: Font.Design { self == .personal ? .serif : .default }

    var background: Color { self == .personal ? Theme.background : Theme.businessBackground }
    var card: Color { self == .personal ? Theme.card : Theme.businessCard }
}

extension Person {
    /// The workspace this person belongs to. It's the hook for per-person
    /// theming (detail hero, row cards) matching their side of the app.
    var workspace: Workspace { isBusiness ? .business : .personal }
}
