import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import ExplorerCore

struct ImagePreviewProvider: PreviewProvider {
    let kind = PreviewKind.image
    func makeView(_ context: PreviewContext) -> AnyView {
        AnyView(ImagePreview(item: context.item, style: context.style, open: context.open))
    }
}

/// Decoded image ready for display. `pixelSize` is after EXIF orientation.
struct DecodedImage: @unchecked Sendable {
    let image: NSImage
    let cgImage: CGImage?
    let pixelSize: CGSize
    let originalPixelSize: CGSize
    let isAnimated: Bool

    var isReduced: Bool { pixelSize.width < originalPixelSize.width - 0.5 }
}

enum ImageDecodeError: Error {
    case unreadable, unsupported, corrupt
}

enum ImageDecoder {
    /// Largest edge decoded for the full viewer. Bigger images are shown as a reduced
    /// copy so a 200 MP panorama cannot exhaust memory.
    static let maxFullPixels = 12_000

    /// Decodes on the calling (background) thread with ImageIO. Applies EXIF
    /// orientation. Animated GIFs are loaded as NSImage so NSImageView can play them.
    static func decode(url: URL, maxPixelSize: Int) -> Result<DecodedImage, ImageDecodeError> {
        guard FileManager.default.isReadableFile(atPath: url.path) else { return .failure(.unreadable) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return .failure(.unsupported)
        }
        guard CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .failure(CGImageSourceGetStatus(source) == .statusComplete ? .unsupported : .corrupt)
        }
        var width = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        var height = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        if orientation >= 5 { swap(&width, &height) }
        let original = CGSize(width: width, height: height)

        let type = CGImageSourceGetType(source).map { $0 as String }
        let isGIF = type.flatMap { UTType($0) }?.conforms(to: .gif) ?? false
        if isGIF && CGImageSourceGetCount(source) > 1, let image = NSImage(contentsOf: url) {
            return .success(DecodedImage(image: image, cgImage: nil, pixelSize: original, originalPixelSize: original, isAnimated: true))
        }

        let limit = max(1, min(maxPixelSize, max(width, height) > 0 ? max(width, height) : maxPixelSize))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return .failure(.corrupt)
        }
        let size = CGSize(width: cg.width, height: cg.height)
        let image = NSImage(cgImage: cg, size: size)
        return .success(DecodedImage(
            image: image, cgImage: cg, pixelSize: size,
            originalPixelSize: original.width > 0 ? original : size, isAnimated: false
        ))
    }

    /// Rotates by quarter turns (display only; the file is never modified).
    static func rotate(_ image: CGImage, quarterTurns: Int) -> CGImage? {
        let turns = ZoomMath.normalizedTurns(quarterTurns)
        if turns == 0 { return image }
        let w = image.width, h = image.height
        let size = ZoomMath.rotatedSize(width: Double(w), height: Double(h), quarterTurns: turns)
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        func context(_ space: CGColorSpace) -> CGContext? {
            CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        // Keep wide-gamut profiles (Display P3) when the context supports them.
        let preferred = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        guard let ctx = preferred.flatMap(context) ?? context(sRGB) else { return nil }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        // Positive turns rotate clockwise on screen.
        ctx.rotate(by: -CGFloat(turns) * .pi / 2)
        ctx.draw(image, in: CGRect(x: -Double(w) / 2, y: -Double(h) / 2, width: Double(w), height: Double(h)))
        return ctx.makeImage()
    }
}

private struct ImagePreview: View {
    let item: FileItem
    let style: PreviewStyle
    let open: () -> Void
    @StateObject private var viewer = ImageViewerController()
    @State private var decoded: DecodedImage?
    @State private var failure: ImageDecodeError?
    @State private var turns = 0
    @State private var rotating = false
    @Environment(\.glass) private var glass

    var body: some View {
        ZStack(alignment: .bottom) {
            if let failure {
                PreviewMessageView(item: item, title: title(for: failure), message: message(for: failure), open: open, compact: style == .compact)
            } else {
                ZoomableImageView(controller: viewer)
                    .opacity(decoded == nil ? 0 : 1)
                    .accessibilityLabel("Image preview of \(item.name)")
                if decoded == nil {
                    ProgressView().controlSize(.small).frame(maxHeight: .infinity)
                }
                if style == .full, let decoded {
                    controls(decoded)
                        .padding(.bottom, 10)
                }
            }
        }
        .task(id: item.id) { await load() }
    }

    private func load() async {
        let url = item.url
        let maxPixels = style == .full ? ImageDecoder.maxFullPixels : 1600
        let result = await Task.detached(priority: .userInitiated) {
            ImageDecoder.decode(url: url, maxPixelSize: maxPixels)
        }.value
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let image):
            decoded = image
            viewer.setImage(image.image, pixelSize: image.pixelSize, animates: image.isAnimated)
        case .failure(let error):
            failure = error
        }
    }

    private func rotate(by delta: Int) {
        guard let decoded, let cg = decoded.cgImage, !rotating else { return }
        rotating = true
        let target = ZoomMath.normalizedTurns(turns + delta)
        Task {
            let rotated = await Task.detached(priority: .userInitiated) {
                ImageDecoder.rotate(cg, quarterTurns: target).map { UncheckedBox(value: $0) }
            }.value
            rotating = false
            guard let rotated else { return }
            turns = target
            let size = CGSize(width: rotated.value.width, height: rotated.value.height)
            viewer.setImage(NSImage(cgImage: rotated.value, size: size), pixelSize: size, animates: false)
        }
    }

    @ViewBuilder
    private func controls(_ decoded: DecodedImage) -> some View {
        PreviewControlBar {
            if !decoded.isAnimated {
                PreviewButton(symbol: "rotate.left", label: "Rotate Left") { rotate(by: -1) }
                PreviewButton(symbol: "rotate.right", label: "Rotate Right") { rotate(by: 1) }
                Divider().frame(height: 16)
            }
            PreviewButton(symbol: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", label: "Fit to Window", isOn: viewer.isFitting) { viewer.fit() }
                .keyboardShortcut("9", modifiers: .command)
            Button { viewer.actualSize() } label: { Text("1:1").font(.system(size: 11, weight: .semibold)) }
                .buttonStyle(GlassIconButtonStyle(isOn: !viewer.isFitting && abs(viewer.scale - 1) < 0.001, size: CGSize(width: 30, height: 24)))
                .keyboardShortcut("0", modifiers: .command)
                .help("Actual Size (⌘0)")
                .accessibilityLabel("Actual size")
            PreviewButton(symbol: "minus.magnifyingglass", label: "Zoom Out (⌘−)") { viewer.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            PreviewButton(symbol: "plus.magnifyingglass", label: "Zoom In (⌘=)") { viewer.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
            Text(ZoomMath.percent(viewer.scale))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .frame(minWidth: 48)
                .accessibilityLabel("Zoom \(ZoomMath.percent(viewer.scale))")
            if decoded.isReduced {
                Text("reduced copy")
                    .font(.system(size: 10))
                    .foregroundStyle(glass.secondaryText)
                    .help("This image is larger than \(ImageDecoder.maxFullPixels) pixels and is shown at reduced resolution.")
            }
        }
    }

    private func title(for error: ImageDecodeError) -> String {
        switch error {
        case .unreadable: return "Can’t read this image"
        case .unsupported: return "This image format isn’t supported"
        case .corrupt: return "This image appears to be damaged"
        }
    }

    private func message(for error: ImageDecodeError) -> String {
        switch error {
        case .unreadable: return "You may not have permission to read it."
        case .unsupported: return "macOS has no decoder for this file. Try opening it in another app."
        case .corrupt: return "The data couldn’t be decoded. The file may be incomplete or corrupted."
        }
    }
}

// MARK: - Zoomable AppKit image view

/// Owns an NSScrollView with magnification. "Fit" re-fits on resize until the user
/// zooms; pinch-to-zoom works natively.
@MainActor
final class ImageViewerController: NSObject, ObservableObject {
    @Published private(set) var scale: Double = 1
    @Published private(set) var isFitting = true
    let scrollView = NSScrollView()
    private let imageView = NSImageView()
    private var pixelSize = CGSize.zero
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let clip = CenteringClipView()
        clip.drawsBackground = false
        scrollView.contentView = clip
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.allowsMagnification = true
        scrollView.minMagnification = ZoomMath.range.lowerBound
        scrollView.maxMagnification = ZoomMath.range.upperBound
        scrollView.postsFrameChangedNotifications = true

        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageFrameStyle = .none
        imageView.animates = true
        imageView.isEditable = false
        imageView.setAccessibilityElement(false)
        scrollView.documentView = imageView

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: scrollView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isFitting = false
                self.scale = Double(self.scrollView.magnification)
            }
        })
        observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: scrollView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isFitting else { return }
                self.fit()
            }
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func setImage(_ image: NSImage, pixelSize: CGSize, animates: Bool) {
        self.pixelSize = pixelSize
        imageView.animates = animates
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: pixelSize)
        if isFitting { fit() } else { apply(scale) }
    }

    func fit() {
        isFitting = true
        // The clip view's frame (in view points) is unaffected by magnification.
        let size = scrollView.contentSize
        let fitted = ZoomMath.fitScale(
            content: (Double(pixelSize.width), Double(pixelSize.height)),
            container: (Double(size.width), Double(size.height))
        )
        apply(fitted)
    }

    func actualSize() {
        isFitting = false
        apply(1)
    }

    func zoomIn() {
        isFitting = false
        apply(ZoomMath.zoomIn(from: scale))
    }

    func zoomOut() {
        isFitting = false
        apply(ZoomMath.zoomOut(from: scale))
    }

    private func apply(_ value: Double) {
        let clamped = min(max(value, ZoomMath.range.lowerBound), ZoomMath.range.upperBound)
        let visible = scrollView.contentView.bounds
        scrollView.setMagnification(CGFloat(clamped), centeredAt: CGPoint(x: visible.midX, y: visible.midY))
        scale = clamped
    }
}

/// Keeps the document centred when it is smaller than the visible area.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        let frame = document.frame
        if rect.width > frame.width { rect.origin.x = (frame.width - rect.width) / 2 }
        if rect.height > frame.height { rect.origin.y = (frame.height - rect.height) / 2 }
        return rect
    }
}

struct ZoomableImageView: NSViewRepresentable {
    let controller: ImageViewerController

    func makeNSView(context: Context) -> NSScrollView { controller.scrollView }
    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}
