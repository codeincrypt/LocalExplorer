import AppKit
import SwiftUI
import ExplorerCore

/// Where a preview is shown. `compact` is the preview pane (small, few controls);
/// `full` is the Gallery view (zoom, page navigation, playback options).
enum PreviewStyle {
    case compact, full
}

struct PreviewContext {
    let item: FileItem
    let style: PreviewStyle
    let services: AppServices
    let open: () -> Void
}

/// A renderer for one `PreviewKind`. Providers are looked up in `PreviewRegistry`; the
/// kind itself is chosen from file content by `PreviewSelector` (ExplorerCore).
@MainActor
protocol PreviewProvider {
    var kind: PreviewKind { get }
    func makeView(_ context: PreviewContext) -> AnyView
}

@MainActor
enum PreviewRegistry {
    private static var providers: [PreviewKind: any PreviewProvider] = {
        var table: [PreviewKind: any PreviewProvider] = [:]
        let all: [any PreviewProvider] = [
            ImagePreviewProvider(),
            PDFPreviewProvider(),
            MediaPreviewProvider(kind: .video),
            MediaPreviewProvider(kind: .audio),
            TextPreviewProvider(),
            QuickLookPreviewProvider(),
            FolderPreviewProvider(),
            FallbackPreviewProvider(),
        ]
        for provider in all { table[provider.kind] = provider }
        return table
    }()

    /// Lets tests or future modules replace a provider.
    static func register(_ provider: any PreviewProvider) {
        providers[provider.kind] = provider
    }

    static func provider(for kind: PreviewKind) -> any PreviewProvider {
        providers[kind] ?? FallbackPreviewProvider()
    }

    /// Reads the file header off the main actor and picks a kind.
    nonisolated static func resolveKind(for item: FileItem) async -> PreviewKind {
        await Task.detached(priority: .userInitiated) {
            let signature = item.isDirectory ? nil : ContentSniffer.sniff(url: item.url)
            return PreviewSelector.kind(for: item, signature: signature)
        }.value
    }
}

/// Resolves and shows the preview for one item. Keyed by the file's identity and
/// modification date, so a changed file reloads and an obsolete request is cancelled
/// (the `.task` is cancelled when the key changes or the view disappears).
struct PreviewHost: View {
    let item: FileItem
    let style: PreviewStyle
    let services: AppServices
    let open: () -> Void
    @State private var kind: PreviewKind?

    private var key: String {
        "\(item.id)|\(item.modificationDate?.timeIntervalSince1970 ?? 0)|\(item.size ?? -1)"
    }

    var body: some View {
        ZStack {
            if let kind {
                PreviewRegistry.provider(for: kind)
                    .makeView(PreviewContext(item: item, style: style, services: services, open: open))
                    .id(key)
            } else {
                // Instant placeholder while the header is read.
                Image(nsImage: FileIconProvider.icon(for: item))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .opacity(0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: key) {
            kind = nil
            let resolved = await PreviewRegistry.resolveKind(for: item)
            if !Task.isCancelled { kind = resolved }
        }
    }
}

// MARK: - Shared preview chrome

/// Floating glass bar used for viewer controls (zoom, pages, playback options).
struct PreviewControlBar<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.glass) private var glass

    var body: some View {
        HStack(spacing: 2) { content }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background {
                Capsule(style: .continuous).fill(.ultraThinMaterial)
                Capsule(style: .continuous).fill(glass.controlFill)
            }
            .overlay { Capsule(style: .continuous).strokeBorder(glass.borderGradient, lineWidth: 0.75) }
            .shadow(color: glass.shadow.opacity(0.6), radius: 8, y: 3)
    }
}

/// Small icon button for preview bars.
struct PreviewButton: View {
    let symbol: String
    let label: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(GlassIconButtonStyle(isOn: isOn, size: CGSize(width: 26, height: 24)))
            .help(label)
            .accessibilityLabel(label)
    }
}

/// Message shown when a preview cannot be produced, with the file icon and an Open
/// action so the user is never stuck.
struct PreviewMessageView: View {
    let item: FileItem
    let title: String
    let message: String?
    let open: () -> Void
    var compact = false
    @Environment(\.glass) private var glass

    var body: some View {
        VStack(spacing: compact ? 6 : 10) {
            Image(nsImage: FileIconProvider.icon(for: item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: compact ? 72 : 128, height: compact ? 72 : 128)
            Text(title)
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(glass.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !compact {
                Button("Open with Default App", action: open)
                    .buttonStyle(GlassCapsuleButtonStyle(prominent: true))
                    .disabled(item.isBrokenSymbolicLink)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Holds a non-Sendable AppKit object while it crosses from a background task to the
/// main actor. Only used for objects that are created in the task and not touched there
/// afterwards.
struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
}

// MARK: - Folder and fallback providers

struct FolderPreviewProvider: PreviewProvider {
    let kind = PreviewKind.folder
    func makeView(_ context: PreviewContext) -> AnyView {
        AnyView(FolderPreview(item: context.item, style: context.style))
    }
}

private struct FolderPreview: View {
    let item: FileItem
    let style: PreviewStyle
    @State private var count: Int?
    @Environment(\.glass) private var glass

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: FileIconProvider.icon(for: item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: style == .full ? 160 : 96, height: style == .full ? 160 : 96)
            if let count {
                Text(DisplayFormat.itemCount(count))
                    .font(.system(size: 11))
                    .foregroundStyle(glass.secondaryText)
            }
        }
        .task(id: item.id) {
            let url = item.url
            count = await Task.detached(priority: .utility) {
                (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.count
            }.value
        }
    }
}

struct FallbackPreviewProvider: PreviewProvider {
    let kind = PreviewKind.fallback
    func makeView(_ context: PreviewContext) -> AnyView {
        let item = context.item
        let message: String
        if item.isBrokenSymbolicLink {
            message = "This alias points to an item that no longer exists."
        } else if !item.isReadable {
            message = "You don’t have permission to read this file."
        } else if item.category == .application {
            message = "Applications open when you double-click them."
        } else if item.category == .archive {
            message = "Archives aren’t expanded for preview. Open the file to extract it."
        } else {
            message = "There’s no built-in preview for this kind of file."
        }
        return AnyView(PreviewMessageView(
            item: item,
            title: context.style == .full ? item.name : item.kindDescription,
            message: message,
            open: context.open,
            compact: context.style == .compact
        ))
    }
}
