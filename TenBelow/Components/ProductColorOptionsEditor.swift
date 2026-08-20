import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct ProductColorOptionsEditor: View {
    @Binding var colors: [ProductColorOption]
    @State private var editingColorIDs: Set<String> = []

    private let presets: [ProductColorOption] = [
        .init(name: "Black", hex: "#171717"),
        .init(name: "White", hex: "#F7F7F5"),
        .init(name: "Gray", hex: "#8E8E93"),
        .init(name: "Red", hex: "#D94242"),
        .init(name: "Blue", hex: "#3578C8"),
        .init(name: "Green", hex: "#3A9657"),
        .init(name: "Yellow", hex: "#E7BD32"),
        .init(name: "Orange", hex: "#E98036"),
        .init(name: "Purple", hex: "#8256B8"),
        .init(name: "Pink", hex: "#DB6B9A"),
        .init(name: "Brown", hex: "#8A6249"),
        .init(name: "Natural", hex: "#E7D7B9"),
    ]

    private var hasDuplicateNames: Bool {
        let names = colors.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return Set(names).count != names.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Available colors")
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)
                Text("Optional. Buyers must choose one of these colors before adding the product to cart.")
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets) { preset in
                        Button {
                            addPreset(preset)
                        } label: {
                            HStack(spacing: 6) {
                                ProductColorSwatch(hex: preset.hex, size: 16)
                                Text(preset.name)
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.72), in: Capsule())
                            .overlay(Capsule().strokeBorder(TBTheme.skyBlue.opacity(0.16)))
                        }
                        .buttonStyle(.plain)
                        .disabled(colors.contains { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame })
                    }
                }
            }

            ForEach($colors) { $color in
                if editingColorIDs.contains(color.id) {
                    colorEditingRow(color: $color)
                } else {
                    savedColorRow(color: color)
                }
            }

            if colors.count < 12 {
                Button {
                    let index = colors.count + 1
                    let color = ProductColorOption(name: "Custom \(index)", hex: "#5B8FD9")
                    colors.append(color)
                    editingColorIDs.insert(color.id)
                } label: {
                    Label("Add custom color", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(TBTheme.accent)
            }

            if hasDuplicateNames {
                Label("Each color needs a unique name.", systemImage: "exclamationmark.triangle.fill")
                    .font(.tbCaption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func addPreset(_ preset: ProductColorOption) {
        guard colors.count < 12,
              !colors.contains(where: { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame })
        else { return }
        colors.append(preset)
    }

    private func colorEditingRow(color: Binding<ProductColorOption>) -> some View {
        let colorID = color.wrappedValue.id
        let canSave = isValidName(color.wrappedValue.name, excluding: colorID)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ColorPicker(
                    "",
                    selection: colorPickerBinding(for: color),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 34)
                .accessibilityLabel("Choose \(color.wrappedValue.name) color")

                TextField("Color name", text: color.name)
                    .textFieldStyle(.plain)
                    .font(.tbBody)
                    .submitLabel(.done)
                    .onSubmit {
                        saveColor(color)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 13))

                Button(role: .destructive) {
                    removeColor(id: colorID)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(color.wrappedValue.name) color")
            }

            Button {
                saveColor(color)
            } label: {
                Label("Save color", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(TBTheme.accent)
            .disabled(!canSave)
            .accessibilityHint("Adds this color to the product's available colors.")
        }
        .padding(10)
        .background(TBTheme.skyLight.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
    }

    private func savedColorRow(color: ProductColorOption) -> some View {
        HStack(spacing: 10) {
            ProductColorSwatch(hex: color.hex, size: 24)

            Text(color.name)
                .font(.tbBodyStrong)
                .foregroundStyle(TBTheme.deepSky)
                .frame(maxWidth: .infinity, alignment: .leading)

            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)

            Button {
                editingColorIDs.insert(color.id)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(color.name) color")

            Button(role: .destructive) {
                removeColor(id: color.id)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(color.name) color")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 15))
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
        )
    }

    private func saveColor(_ color: Binding<ProductColorOption>) {
        let trimmedName = color.wrappedValue.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidName(trimmedName, excluding: color.wrappedValue.id) else { return }
        color.wrappedValue.name = trimmedName
        color.wrappedValue.hex = ProductColorOption.normalizedHex(color.wrappedValue.hex)
        editingColorIDs.remove(color.wrappedValue.id)
    }

    private func removeColor(id: String) {
        editingColorIDs.remove(id)
        colors.removeAll { $0.id == id }
    }

    private func isValidName(_ name: String, excluding id: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !colors.contains {
            $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private func colorPickerBinding(for option: Binding<ProductColorOption>) -> Binding<Color> {
        Binding(
            get: { Color(productHex: option.wrappedValue.hex) },
            set: { newColor in
                option.wrappedValue.hex = newColor.productHexString ?? option.wrappedValue.hex
            }
        )
    }
}

struct ProductColorSwatch: View {
    let hex: String?
    var size: CGFloat = 20

    var body: some View {
        Circle()
            .fill(Color(productHex: hex))
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.primary.opacity(0.16), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

extension Color {
    init(productHex: String?) {
        let normalized = ProductColorOption.normalizedHex(productHex) ?? "#8E8E93"
        let value = UInt64(normalized.dropFirst(), radix: 16) ?? 0x8E8E93
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var productHexString: String? {
        #if canImport(UIKit)
        let color = UIColor(self)
        guard let components = color.cgColor.components else { return nil }
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        if components.count >= 3 {
            red = components[0]
            green = components[1]
            blue = components[2]
        } else if let white = components.first {
            red = white
            green = white
            blue = white
        } else {
            return nil
        }
        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
        #else
        return nil
        #endif
    }
}
