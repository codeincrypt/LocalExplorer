import AppKit
import Quartz
import SwiftUI
import ExplorerCore

// MARK: - Text and source code

struct TextPreviewProvider: PreviewProvider {
    let kind = PreviewKind.text
    func makeView(_ context: PreviewContext) -> AnyView {
        AnyView(TextPreview(item: context.item, style: context.style, open: context.open))
    }
}

private struct TextPreview: View {
    let item: FileItem
    let style: PreviewStyle
    let open: () -> Void
    @State private var result: TextPreviewResult?
    @AppStorage("TextPreviewWraps") private var wraps = true
    @Environment(\.glass) private var glass

    /// The pane only needs the beginning of the file.
    private var limit: Int { style == .full ? TextPreviewLoader.defaultLimit : 64 * 1024 }

    var body: some View {
        Group {
            switch result {
            case nil:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .binary?:
                PreviewMessageView(item: item, title: "Binary file", message: "This file contains binary data and isn’t shown as text.", open: open, compact: style == .compact)
            case .unreadable(let reason)?:
                PreviewMessageView(item: item, title: "Can’t read this file", message: reason, open: open, compact: style == .compact)
            case .text(let content)?:
                VStack(spacing: 0) {
                    if style == .full { header(content) }
                    if content.text.isEmpty {
                        Text("This file is empty.")
                            .font(.system(size: 12))
                            .foregroundStyle(glass.secondaryText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        PlainTextView(text: content.text, wraps: wraps, fontSize: style == .full ? 12 : 10.5)
                            .accessibilityLabel("Text preview of \(item.name)")
                    }
                    if style == .compact && content.isTruncated {
                        Text("Showing the beginning of the file")
                            .font(.system(size: 10))
                            .foregroundStyle(glass.secondaryText)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .task(id: item.id) {
            let url = item.url
            let limit = self.limit
            let loaded = await Task.detached(priority: .userInitiated) {
                TextPreviewLoader.load(url: url, limit: limit)
            }.value
            if !Task.isCancelled { result = loaded }
        }
    }

    private func header(_ content: TextPreviewContent) -> some View {
        HStack(spacing: 10) {
            Text(content.encodingName)
            Text("\(content.lineCount.formatted()) line\(content.lineCount == 1 ? "" : "s")")
            Text(DisplayFormat.byteCount(content.totalBytes))
            if content.isTruncated {
                Label("Showing first \(DisplayFormat.byteCount(Int64(limit)))", systemImage: "scissors")
                    .foregroundStyle(.orange)
            }
            Spacer()
            Toggle("Wrap lines", isOn: $wraps)
                .toggleStyle(.checkbox)
                .controlSize(.small)
        }
        .font(.system(size: 11))
        .foregroundStyle(glass.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(glass.hairline).frame(height: 1) }
    }
}

/// Read-only, selectable NSTextView. Link and data detection are off so nothing in the
/// text is ever turned into a clickable remote link or looked up.
struct PlainTextView: NSViewRepresentable {
    let text: String
    let wraps: Bool
    let fontSize: CGFloat

    final class Coordinator {
        var text: String?
        var wraps: Bool?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.enabledTextCheckingTypes = 0
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .labelColor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        if context.coordinator.wraps != wraps {
            context.coordinator.wraps = wraps
            scroll.hasHorizontalScroller = !wraps
            textView.isHorizontallyResizable = !wraps
            textView.textContainer?.widthTracksTextView = wraps
            textView.textContainer?.containerSize = NSSize(
                width: wraps ? scroll.contentSize.width : CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            if wraps { textView.frame.size.width = scroll.contentSize.width }
        }
        if context.coordinator.text != text {
            context.coordinator.text = text
            textView.string = text
            textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            textView.scroll(.zero)
        }
    }
}

// MARK: - Quick Look (rich documents)

struct QuickLookPreviewProvider: PreviewProvider {
    let kind = PreviewKind.quickLook
    func makeView(_ context: PreviewContext) -> AnyView {
        AnyView(QuickLookPreview(item: context.item))
    }
}

/// Embedded Quick Look for Office/iWork documents, RTF, SVG and fonts. Quick Look shows
/// a generic icon when no generator handles the type, so it is only used for the types
/// `PreviewSelector` routes here.
private struct QuickLookPreview: View {
    let item: FileItem

    var body: some View {
        QuickLookRepresentable(url: item.url)
            .accessibilityLabel("Quick Look preview of \(item.name)")
    }
}

struct QuickLookRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = false
        view.shouldCloseWithWindow = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if view.previewItem?.previewItemURL != url {
            view.previewItem = url as NSURL
        }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
