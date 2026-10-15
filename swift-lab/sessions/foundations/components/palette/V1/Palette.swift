import LabHost
import SwiftUI

/// Every colour `Palette` defines, each resolving for light or dark: the
/// states GitHub's colours stand for, the panel's surfaces, and what each
/// kind and state draws in.
public let variant = LabVariant { PaletteSheet() }

struct PaletteSheet: View {
    private let states: [(String, Color)] = [
        ("green", Palette.green), ("gray", Palette.gray), ("purple", Palette.purple), ("red", Palette.red),
        ("amber", Palette.amber), ("accent", Palette.accent), ("lease", Palette.lease),
    ]
    private let surfaces: [(String, Color)] = [
        ("panel", Palette.panel), ("header", Palette.header), ("chrome", Palette.chrome), ("track", Palette.track),
        ("raised", Palette.raised), ("fill", Palette.fill), ("hover", Palette.hover), ("pressed", Palette.pressed),
        ("border", Palette.border), ("separator", Palette.separator),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("States", states)
            section("Surfaces", surfaces)
            Specimen(title: "a row's colour by kind and state (Palette.color(_:kind:))") {
                HStack(spacing: 10) {
                    ForEach(Array(Gallery.rows.enumerated()), id: \.offset) { _, row in
                        Image(systemName: Palette.symbol(row.state, kind: row.kind))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.color(row.state, kind: row.kind))
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.color(row.state, kind: row.kind).opacity(0.14)))
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 620, alignment: .leading)
        .background(Palette.panel)
    }

    private func section(_ title: String, _ colors: [(String, Color)]) -> some View {
        Specimen(title: title) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(104), spacing: 10), count: 5), alignment: .leading, spacing: 10) {
                ForEach(colors, id: \.0) { name, color in
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: Grid.radius, style: .continuous)
                            .fill(color)
                            .overlay(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
                            .frame(height: 44)
                        Text(name).font(TypeScale.meta).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
