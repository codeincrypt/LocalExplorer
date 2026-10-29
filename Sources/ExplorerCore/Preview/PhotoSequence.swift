import Foundation

/// The photos of a folder in display order, with the one being viewed. Pure value type so
/// the arrow-key navigation of the photo viewer can be tested without UI.
public struct PhotoSequence: Equatable, Sendable {
    public let ids: [String]
    public private(set) var index: Int?

    public init(ids: [String], current: String?) {
        self.ids = ids
        self.index = current.flatMap { ids.firstIndex(of: $0) }
    }

    public var currentID: String? { index.map { ids[$0] } }
    public var count: Int { ids.count }
    public var hasPrevious: Bool { (index ?? 0) > 0 }
    public var hasNext: Bool { index.map { $0 < ids.count - 1 } ?? false }

    /// "3 of 24", or `nil` when nothing is being viewed.
    public var positionDescription: String? {
        index.map { "\($0 + 1) of \(ids.count)" }
    }

    /// Id reached by moving `offset` photos from the current one, stopping at either end
    /// (no wrap-around). `nil` when there is no current photo or it would not move.
    public func target(offset: Int) -> String? {
        guard let index, !ids.isEmpty else { return nil }
        let clamped = min(max(index + offset, 0), ids.count - 1)
        return clamped == index ? nil : ids[clamped]
    }

    public var first: String? { ids.first }
    public var last: String? { ids.last }
}
