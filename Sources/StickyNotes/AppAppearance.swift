import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable {
    case light, dark

    private static let preference = "Appearance.mode"

    var title: String { self == .light ? "浅色" : "深色" }
    var symbol: String { self == .light ? "sun.max" : "moon" }

    @MainActor
    static func restore() {
        if let rawValue = AppIdentity.preferences.string(forKey: preference),
           let appearance = Self(rawValue: rawValue) {
            appearance.apply()
        }
    }

    @MainActor
    func select() {
        AppIdentity.preferences.set(rawValue, forKey: Self.preference)
        apply()
    }

    @MainActor
    private func apply() {
        NSApp.appearance = NSAppearance(named: self == .light ? .aqua : .darkAqua)
    }
}

struct AppearancePicker: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let current: AppAppearance = colorScheme == .dark ? .dark : .light
        let next: AppAppearance = current == .dark ? .light : .dark

        Button {
            next.select()
        } label: {
            HStack(spacing: 3) {
                ForEach(AppAppearance.allCases, id: \.self) { appearance in
                    let selected = appearance == current
                    Image(systemName: appearance.symbol)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(width: 32, height: 25)
                        .background(selected ? selectionFill : .clear, in: Capsule())
                }
            }
            .padding(3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .glassControls(in: Capsule())
        .accessibilityLabel("切换外观")
        .accessibilityValue(current.title)
        .help("切换为\(next.title)外观")
    }

    private var selectionFill: Color {
        Color.white.opacity(colorScheme == .dark ? 0.18 : 0.76)
    }
}

struct GlassActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        let fill = prominent && isEnabled ? Color.accentColor.opacity(0.25) : .clear

        configuration.label
            .fontWeight(prominent ? .semibold : .medium)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 27)
            .background(fill, in: Capsule())
            .glassControls(in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.76 : 1) : 0.45)
            .contentShape(Capsule())
    }
}

private struct FrostedGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct GlassBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color?

    var body: some View {
        let panelTint = if colorScheme == .dark {
            tint?.opacity(0.62) ?? Color(white: 0.045).opacity(0.30)
        } else {
            (tint ?? Color(nsColor: .windowBackgroundColor)).opacity(0.52)
        }

        ZStack {
            FrostedGlass()
            panelTint
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func glassPanel(in shape: some InsettableShape, tint: Color? = nil) -> some View {
        background { GlassBackdrop(tint: tint) }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.48), .white.opacity(0.12), .black.opacity(0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
            }
    }

    func glassCard(in shape: some InsettableShape, tint: Color = .clear) -> some View {
        background {
            shape.fill(tint)
                .background(.thinMaterial, in: shape)
        }
        .overlay {
            shape.strokeBorder(.white.opacity(0.16), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    func glassControls(in shape: some InsettableShape) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            glassCard(in: shape)
        }
        #else
        glassCard(in: shape)
        #endif
    }
}
