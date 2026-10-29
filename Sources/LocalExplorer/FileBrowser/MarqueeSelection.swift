import AppKit
import SwiftUI
import ExplorerCore

/// Frames of the realised items, in the scrolling content's coordinate space.
private struct ItemFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private let marqueeSpace = "marqueeContent"

extension View {
    /// Publishes this item's frame so a drag on empty space can select it.
    func marqueeItem(_ id: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: ItemFramesKey.self, value: [id: proxy.frame(in: .named(marqueeSpace))])
            }
        }
    }

    /// Rubber-band selection: dragging on empty space draws a rectangle and selects the
    /// items it touches. Command or Shift keeps the existing selection. Also clears the
    /// selection on a plain click and shows folder actions on right-click.
    ///
    /// Apply to the scroll content, sized to fill the viewport so empty space is hittable.
    func marqueeSelection(tab: TabModel, model: WindowModel, focus: FocusState<FocusTarget?>.Binding) -> some View {
        modifier(MarqueeSelection(tab: tab, model: model, focus: focus))
    }
}

private struct MarqueeSelection: ViewModifier {
    @ObservedObject var tab: TabModel
    let model: WindowModel
    var focus: FocusState<FocusTarget?>.Binding

    @State private var liveFrames: [String: CGRect] = [:]
    /// Frames seen during the current drag; keeps items that scroll out of the lazy grid.
    @State private var dragFrames: [String: CGRect] = [:]
    @State private var rect: CGRect?
    @State private var base: Set<String> = []

    func body(content: Content) -> some View {
        content
            .background {
                BackgroundClickCatcher(tab: tab, model: model, focus: focus)
                    .gesture(drag)
            }
            .overlay(alignment: .topLeading) {
                if let rect {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.18))
                        .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: marqueeSpace)
            .onPreferenceChange(ItemFramesKey.self) { frames in
                liveFrames = frames
                if rect != nil { dragFrames.merge(frames) { $1 } }
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(marqueeSpace))
            .onChanged { value in
                if rect == nil {
                    let flags = NSEvent.modifierFlags
                    base = flags.contains(.command) || flags.contains(.shift) ? tab.selection : []
                    dragFrames = liveFrames
                    focus.wrappedValue = .fileList
                }
                let marquee = MarqueeMath.rect(from: value.startLocation, to: value.location)
                rect = marquee
                let order = tab.itemIDs
                let present = Set(order)
                let hits = MarqueeMath.hits(in: marquee, frames: dragFrames).intersection(present)
                tab.selectionModel.applyMarquee(hits: hits, base: base, order: order)
            }
            .onEnded { _ in
                rect = nil
                dragFrames = [:]
            }
    }
}
