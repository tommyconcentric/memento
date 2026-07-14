import SwiftUI
import UIKit

/// Memento's palette — a Greek island summer, Mamma Mia style:
/// Aegean water, whitewashed walls, bougainvillea, taverna pots and sun.
enum Theme {
    static let aegean = Color(red: 0.118, green: 0.431, blue: 0.624)        // #1E6E9F
    static let sky = Color(red: 0.310, green: 0.651, blue: 0.835)           // #4FA6D5
    static let bougainvillea = Color(red: 0.851, green: 0.310, blue: 0.557) // #D94F8E
    static let sunshine = Color(red: 0.949, green: 0.757, blue: 0.306)      // #F2C14E
    static let olive = Color(red: 0.478, green: 0.545, blue: 0.310)         // #7A8B4F
    static let terracotta = Color(red: 0.788, green: 0.435, blue: 0.290)    // #C96F4A
    static let gold = Color(red: 0.753, green: 0.541, blue: 0.176)          // #C08A2D
    static let bark = Color(red: 0.478, green: 0.333, blue: 0.224)          // #7A5539 — tree trunks

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

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}
