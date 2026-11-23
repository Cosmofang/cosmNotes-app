import SwiftUI

/// Places each project at its ideal width and starts a new line before it crosses the viewport.
struct WorkProjectLayout: Layout {
    static let rowHeight: CGFloat = 30
    private let spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let frames = frames(for: subviews, width: width)
        return CGSize(width: width ?? frames.map(\.maxX).max() ?? 0, height: frames.last?.maxY ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(for: subviews, width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat?) -> [CGRect] {
        let available = width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var result: [CGRect] = []
        for subview in subviews {
            let chipWidth = min(subview.sizeThatFits(.unspecified).width, available)
            if x > 0 && x + chipWidth > available {
                x = 0
                y += Self.rowHeight + spacing
            }
            result.append(CGRect(x: x, y: y, width: chipWidth, height: Self.rowHeight))
            x += chipWidth + spacing
        }
        return result
    }
}
