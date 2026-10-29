import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Modifier state relevant to selection clicks.
public struct SelectionModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// Command: toggle membership.
    public static let toggle = SelectionModifiers(rawValue: 1 << 0)
    /// Shift: extend a contiguous range from the anchor.
    public static let extend = SelectionModifiers(rawValue: 1 << 1)
}

public enum MoveDirection: Sendable {
    case up, down, left, right, home, end
}

/// How items are laid out, so arrow keys move predictably.
public enum ItemArrangement: Sendable, Equatable {
    /// A single vertical list (Details).
    case list
    /// Rows filled left to right (Tiles).
    case rowMajor(columns: Int)
    /// Columns filled top to bottom (Compact List).
    case columnMajor(rows: Int)
    /// A single horizontal strip (Gallery).
    case strip
}

/// Selection state shared by all view modes: the selected set, the range anchor and the
/// keyboard cursor. Identifiers are `FileItem.id`.
public struct SelectionModel: Equatable, Sendable {
    public private(set) var selected: Set<String> = []
    public private(set) var anchor: String?
    public private(set) var cursor: String?

    public init() {}

    public init(selected: Set<String>, anchor: String? = nil, cursor: String? = nil) {
        self.selected = selected
        self.anchor = anchor ?? cursor
        self.cursor = cursor ?? anchor
    }

    public var isEmpty: Bool { selected.isEmpty }
    public var count: Int { selected.count }

    /// Replace the selection wholesale (e.g. from a native table).
    public mutating func replace(with ids: Set<String>, order: [String]) {
        selected = ids
        if let cursor, ids.contains(cursor) { return }
        let last = order.last { ids.contains($0) }
        cursor = last
        anchor = order.first { ids.contains($0) } ?? last
    }

    public mutating func click(_ id: String, order: [String], modifiers: SelectionModifiers = []) {
        if modifiers.contains(.extend), let anchor, order.contains(anchor) {
            let range = Self.range(from: anchor, to: id, in: order)
            selected = modifiers.contains(.toggle) ? selected.union(range) : Set(range)
            cursor = id
        } else if modifiers.contains(.toggle) {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            anchor = id
            cursor = id
        } else {
            selected = [id]
            anchor = id
            cursor = id
        }
    }

    public mutating func selectAll(order: [String]) {
        selected = Set(order)
        anchor = order.first
        cursor = order.last
    }

    public mutating func clear() {
        selected.removeAll()
        anchor = nil
        cursor = nil
    }

    /// Moves the cursor; with `extend` grows the range from the anchor, otherwise
    /// selects only the new cursor. Returns the new cursor id.
    @discardableResult
    public mutating func move(_ direction: MoveDirection, order: [String], arrangement: ItemArrangement, extend: Bool = false) -> String? {
        guard !order.isEmpty else { return nil }
        let currentIndex = cursor.flatMap { order.firstIndex(of: $0) }
        let newIndex: Int
        if let currentIndex {
            newIndex = Self.target(from: currentIndex, direction: direction, count: order.count, arrangement: arrangement)
        } else {
            // No cursor yet: moving "backwards" starts from the end, otherwise the start.
            switch direction {
            case .up, .left, .end: newIndex = order.count - 1
            default: newIndex = 0
            }
        }
        let id = order[newIndex]
        if extend, let anchor, order.contains(anchor) {
            selected = Set(Self.range(from: anchor, to: id, in: order))
            cursor = id
        } else {
            selected = [id]
            anchor = id
            cursor = id
        }
        return id
    }

    /// Applies a rubber-band drag: the selection becomes `base` (the selection when the
    /// drag started, empty unless extending) plus everything the rectangle touches.
    public mutating func applyMarquee(hits: Set<String>, base: Set<String>, order: [String]) {
        selected = base.union(hits)
        cursor = order.last { hits.contains($0) } ?? order.last { selected.contains($0) }
        anchor = order.first { hits.contains($0) } ?? cursor
    }

    /// Drops identifiers that disappeared after a refresh, keeping the rest stable.
    public mutating func reconcile(with order: [String]) {
        let present = Set(order)
        selected.formIntersection(present)
        if let a = anchor, !present.contains(a) { anchor = nil }
        if let c = cursor, !present.contains(c) { cursor = nil }
        if cursor == nil { cursor = order.first { selected.contains($0) } }
        if anchor == nil { anchor = cursor }
    }

    static func range(from a: String, to b: String, in order: [String]) -> [String] {
        guard let i = order.firstIndex(of: a), let j = order.firstIndex(of: b) else { return [b] }
        return Array(order[min(i, j)...max(i, j)])
    }

    static func target(from index: Int, direction: MoveDirection, count: Int, arrangement: ItemArrangement) -> Int {
        let last = count - 1
        func clamp(_ v: Int) -> Int { min(max(v, 0), last) }
        switch direction {
        case .home: return 0
        case .end: return last
        default: break
        }
        switch arrangement {
        case .list:
            switch direction {
            case .up: return clamp(index - 1)
            case .down: return clamp(index + 1)
            default: return index
            }
        case .strip:
            switch direction {
            case .left, .up: return clamp(index - 1)
            case .right, .down: return clamp(index + 1)
            default: return index
            }
        case .rowMajor(let columns):
            let c = max(1, columns)
            switch direction {
            case .left: return clamp(index - 1)
            case .right: return clamp(index + 1)
            case .up: return index - c >= 0 ? index - c : index
            case .down: return index + c <= last ? index + c : (index / c < last / c ? last : index)
            default: return index
            }
        case .columnMajor(let rows):
            let r = max(1, rows)
            switch direction {
            case .up: return clamp(index - 1)
            case .down: return clamp(index + 1)
            case .left: return index - r >= 0 ? index - r : index
            case .right: return index + r <= last ? index + r : (index / r < last / r ? last : index)
            default: return index
            }
        }
    }
}

public enum MarqueeMath {
    /// A rectangle spanning two drag points, whichever corner it was dragged towards.
    public static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// Identifiers whose frames the marquee touches (edges count, like Explorer/Finder).
    public static func hits(in marquee: CGRect, frames: [String: CGRect]) -> Set<String> {
        var result: Set<String> = []
        for (id, frame) in frames
        where marquee.minX <= frame.maxX && marquee.maxX >= frame.minX
            && marquee.minY <= frame.maxY && marquee.maxY >= frame.minY {
            result.insert(id)
        }
        return result
    }
}

public enum GridLayoutMath {
    /// Number of fixed-width columns that fit, matching `LazyVGrid` adaptive layout.
    public static func columns(availableWidth: Double, itemWidth: Double, spacing: Double, padding: Double = 0) -> Int {
        let usable = availableWidth - 2 * padding
        guard itemWidth > 0, usable > 0 else { return 1 }
        return max(1, Int((usable + spacing) / (itemWidth + spacing)))
    }

    /// Number of fixed-height rows that fit in a column (Compact List).
    public static func rows(availableHeight: Double, rowHeight: Double, spacing: Double, padding: Double = 0) -> Int {
        columns(availableWidth: availableHeight, itemWidth: rowHeight, spacing: spacing, padding: padding)
    }
}
