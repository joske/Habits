//
//  ColorPalettePicker.swift
//  Habits
//
//  Created by Jos Dehaes on 13/09/2026.
//

import SwiftUI

struct ColorPalettePicker: View {
    @Binding var selection: Int

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8), count: 10)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<HabitPalette.count, id: \.self) { index in
                Button {
                    selection = index
                } label: {
                    Circle()
                        .fill(HabitPalette.color(for: index))
                        .overlay {
                            if index == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 1)
                            }
                        }
                        .frame(height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(index + 1)")
                .accessibilityAddTraits(
                    index == selection ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 4)
    }
}
