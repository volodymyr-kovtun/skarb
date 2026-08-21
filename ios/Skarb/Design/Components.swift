import SwiftUI

// MARK: - Type

extension Font {
    /// The display face — headings and every figure big enough to be read as a headline.
    /// The web sets Bricolage Grotesque here; on iOS the system face carries it, which keeps
    /// Dynamic Type, the SF numeral set and the platform's own rhythm intact.
    static func display(_ size: CGFloat, _ weight: Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

/// The micro-label above a figure — stat tiles, the net-worth hero, day headings.
struct MicroLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Palette.faint)
    }
}

// MARK: - Surfaces

/// The card every section sits on: the web's `rounded-card bg-surface shadow-card`.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: .rect(cornerRadius: Palette.Radius.card))
            .shadow(color: .black.opacity(0.05), radius: 17, y: 7)
    }
}

/// A card's heading: title, the window it counts over, and an optional control opposite.
struct CardHeader<Action: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.display(17))
                // Where a card counts from — said out loud, because no two cards here count
                // the same days.
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.faint)
                }
            }
            Spacer(minLength: 12)
            action
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}

extension CardHeader where Action == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Controls

/// Compact pill switcher — display currency, report periods, the spending breakdown.
/// Scrolls rather than wrapping, so every pill stays one line high on a narrow phone.
struct SegmentedPills<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var accessibilityLabel: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(options, id: \.value) { option in
                    Button {
                        selection = option.value
                    } label: {
                        Text(option.label)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(selection == option.value ? Palette.ink : Palette.muted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background {
                                if selection == option.value {
                                    Capsule().fill(Palette.surface)
                                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == option.value ? [.isSelected] : [])
                }
            }
            .padding(4)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(Palette.surface2, in: .capsule)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A filter control: same height and shape as a button, quieter. Turns accent when it is on.
struct FilterPill<Label: View>: View {
    var isOn: Bool = false
    var action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? Palette.paper : Palette.muted)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(isOn ? Palette.accent : Palette.surface2, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// The app's primary action — a filled accent capsule, matching the web's `btnPrimary`.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Palette.accent, in: .capsule)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var skarbPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// A text field wearing the web's `inputCls`: a quiet filled row that lights up on focus.
struct SkarbFieldStyle: ViewModifier {
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Palette.surface2, in: .rect(cornerRadius: Palette.Radius.row))
            .overlay {
                RoundedRectangle(cornerRadius: Palette.Radius.row)
                    .strokeBorder(Palette.accent, lineWidth: focused ? 1.5 : 0)
            }
    }
}

extension View {
    func skarbField() -> some View { modifier(SkarbFieldStyle()) }
}

// MARK: - Small pieces

/// A colored dot for legends, account rows and tag lists.
struct ColorDot: View {
    let hex: String
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(HSL.swatch(hex))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A category's emoji on a wash of its own color. The wash follows the appearance.
struct CategoryDot: View {
    let category: Category?
    var size: CGFloat = 40

    var body: some View {
        let hex = category?.color ?? "#91897C"
        RoundedRectangle(cornerRadius: Palette.Radius.tile)
            .fill(HSL.tint(hex))
            .frame(width: size, height: size)
            .overlay {
                Text(category?.emoji ?? "·").font(.system(size: size * 0.42))
            }
            .accessibilityHidden(true)
    }
}

/// A small chip — the `internal` / `excluded` markers and tag labels on a transaction row.
struct Chip: View {
    let text: String
    var hex: String?

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(hex.map { HSL.swatch($0) } ?? Palette.faint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(hex.map { HSL.tint($0) } ?? Palette.surface2, in: .capsule)
            .lineLimit(1)
    }
}

/// Money, in the shape the rest of the app expects: tabular figures, income in green,
/// anything that doesn't count in grey.
struct Money: View {
    let amount: Decimal
    let currency: String
    var signed = false
    var muted = false
    var decimals = 2
    var font: Font = .system(size: 14.5, weight: .semibold)

    var body: some View {
        Text(Format.money(amount, currency, signed: signed, decimals: decimals))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(muted ? Palette.faint : (signed && amount > 0 ? Palette.income : Palette.ink))
    }
}

/// The full-screen "nothing here" note every list falls back to.
struct EmptyNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Palette.faint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 44)
    }
}

/// One row of a settings-style list inside a `Card`.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var tint: Color = Palette.muted
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Palette.faint)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, icon: String? = nil, tint: Color = Palette.muted) {
        self.init(title: title, subtitle: subtitle, icon: icon, tint: tint) { EmptyView() }
    }
}

/// The chevron that says a row opens something.
struct DisclosureChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.faint)
    }
}
