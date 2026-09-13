//
//  HabitPalette.swift
//  Habits
//
//  Created by Jos Dehaes on 13/09/2026.
//

import SwiftUI
import UIKit

/// Loop's 20 habit colors (lightPalette / darkPalette from uhabits' colors.xml).
/// Like Loop, the `color` column stores an index into this palette.
enum HabitPalette {
    /// Loop's default color for a new habit (teal).
    static let defaultIndex = 8

    static var count: Int { light.count }

    private static let light: [UInt32] = [
        0xD32F2F, 0xE64A19, 0xF57C00, 0xFF8F00, 0xF9A825,
        0xAFB42B, 0x7CB342, 0x388E3C, 0x00897B, 0x00ACC1,
        0x039BE5, 0x1976D2, 0x303F9F, 0x5E35B1, 0x8E24AA,
        0xD81B60, 0x5D4037, 0x424242, 0x757575, 0x9E9E9E,
    ]

    private static let dark: [UInt32] = [
        0xEF9A9A, 0xFFAB91, 0xFFCC80, 0xFFECB3, 0xFFF59D,
        0xE6EE9C, 0xC5E1A5, 0x69F0AE, 0x80CBC4, 0x80DEEA,
        0x81D4FA, 0x64B5F6, 0x9FA8DA, 0xB39DDB, 0xCE93D8,
        0xF48FB1, 0xBCAAA4, 0xF5F5F5, 0xE0E0E0, 0x9E9E9E,
    ]

    /// Palette color for an index, following the system light/dark appearance.
    /// Out-of-range indices wrap around, so an unexpected value from an
    /// imported database still yields a usable color.
    static func color(for index: Int) -> Color {
        let i = ((index % count) + count) % count
        return Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(rgb: dark[i]) : UIColor(rgb: light[i])
            })
    }
}

extension Habit {
    /// The habit's palette color.
    var tint: Color { HabitPalette.color(for: color) }
}

extension UIColor {
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
