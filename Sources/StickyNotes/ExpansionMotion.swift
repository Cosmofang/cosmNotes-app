import SwiftUI

enum ExpansionMotion {
    static let duration: TimeInterval = 0.3
    static let animation = Animation.easeOut(duration: duration)
    static let transition = AnyTransition.asymmetric(insertion: .opacity, removal: .identity)
}

struct ExpansionDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                let expanding = !configuration.isExpanded
                withAnimation(expanding ? ExpansionMotion.animation : nil) {
                    configuration.isExpanded = expanding
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    configuration.label
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "已展开" : "已收起")

            if configuration.isExpanded {
                configuration.content
                    .transition(ExpansionMotion.transition)
            }
        }
    }
}
