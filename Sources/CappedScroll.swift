import SwiftUI

/// Shows its content at natural height up to `maxHeight`, then scrolls. Cards put their variable
/// part (command, details, question and options) in one of these so the action buttons below it
/// always stay on screen, however long the agent's text is.
struct CappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @UIState private var natural: CGFloat = 0

    var body: some View {
        let limit = max(maxHeight, 80)
        ScrollView(.vertical, showsIndicators: natural > limit) {
            content
                .background(GeometryReader { g in
                    Color.clear.preference(key: CappedScrollHeightKey.self, value: g.size.height)
                })
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(natural, limit))
        .onPreferenceChange(CappedScrollHeightKey.self) { natural = $0 }
    }
}

struct CappedScrollHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension NSScreen {
    /// Tallest a card may be on this screen: the visible area minus a margin.
    var maxCardHeight: CGFloat { max(visibleFrame.height - 24, 320) }
}
