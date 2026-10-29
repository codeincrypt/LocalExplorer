import AppKit
import SwiftUI
import ExplorerCore

// MARK: - Theme

/// Glassmorphism tokens. The window is a translucent backdrop (desktop blur plus a soft
/// tinted gradient) and every functional area floats above it as a frosted panel with
/// a light top-edge highlight, hairline border and soft shadow.
struct GlassTheme {
    let tint: GlassTint
    let intensity: GlassIntensity
    let useLiquidGlass: Bool
    let scheme: ColorScheme
    var customColor = GlassColor.default
    /// 0 is the normal frosted look; higher values let the backdrop show through.
    var transparency: Double = 0

    var isDark: Bool { scheme == .dark }

    /// How much of the panel fill (material, wash, highlight) is drawn.
    var panelOpacity: Double {
        1 - min(max(transparency, 0), AppPreferences.maxGlassTransparency)
    }

    /// Analogous colours derived from the user's colour: the colour itself plus two
    /// neighbouring hues.
    private var customPalette: [Color] {
        let base = NSColor(srgbRed: customColor.red, green: customColor.green, blue: customColor.blue, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        func shifted(_ delta: CGFloat, brightness factor: CGFloat) -> Color {
            let h = (hue + delta).truncatingRemainder(dividingBy: 1)
            return Color(hue: h < 0 ? h + 1 : h, saturation: saturation, brightness: min(brightness * factor, 1))
        }
        return [
            Color(.sRGB, red: customColor.red, green: customColor.green, blue: customColor.blue, opacity: 1),
            shifted(0.08, brightness: 0.95),
            shifted(-0.06, brightness: 1.05),
        ]
    }

    /// Colours of the blurred light "blobs" behind the panels.
    var palette: [Color] {
        switch tint {
        case .ocean: return [Color(red: 0.16, green: 0.42, blue: 0.98), Color(red: 0.42, green: 0.25, blue: 0.95), Color(red: 0.10, green: 0.75, blue: 0.95)]
        case .aurora: return [Color(red: 0.55, green: 0.25, blue: 0.95), Color(red: 0.10, green: 0.80, blue: 0.70), Color(red: 0.95, green: 0.35, blue: 0.75)]
        case .sunset: return [Color(red: 0.98, green: 0.45, blue: 0.30), Color(red: 0.90, green: 0.25, blue: 0.55), Color(red: 1.00, green: 0.75, blue: 0.30)]
        case .graphite: return [Color(white: 0.45), Color(white: 0.30), Color(white: 0.60)]
        case .mint: return [Color(red: 0.15, green: 0.75, blue: 0.55), Color(red: 0.20, green: 0.55, blue: 0.95), Color(red: 0.55, green: 0.90, blue: 0.60)]
        case .custom: return customPalette
        }
    }

    var panelMaterial: Material {
        switch intensity {
        case .clear: return .ultraThinMaterial
        case .balanced: return .thinMaterial
        case .frosted: return .regularMaterial
        }
    }

    /// Milky wash on top of the material; stronger in light mode.
    var panelWash: Color {
        switch intensity {
        case .clear: return .white.opacity(isDark ? 0.02 : 0.10)
        case .balanced: return .white.opacity(isDark ? 0.04 : 0.22)
        case .frosted: return .white.opacity(isDark ? 0.06 : 0.32)
        }
    }

    var borderGradient: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(isDark ? 0.26 : 0.85), .white.opacity(isDark ? 0.05 : 0.25)],
            startPoint: .top, endPoint: .bottom
        )
    }

    var shadow: Color { .black.opacity(isDark ? 0.40 : 0.14) }
    var controlFill: Color { .white.opacity(isDark ? 0.08 : 0.45) }
    var controlHover: Color { .white.opacity(isDark ? 0.14 : 0.70) }
    var controlPressed: Color { .white.opacity(isDark ? 0.20 : 0.85) }
    var hairline: Color { isDark ? .white.opacity(0.10) : .black.opacity(0.08) }
    var secondaryText: Color { .primary.opacity(isDark ? 0.62 : 0.58) }

    var selectionFill: LinearGradient {
        LinearGradient(colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.75)], startPoint: .top, endPoint: .bottom)
    }

    var softSelectionFill: Color { Color.accentColor.opacity(isDark ? 0.30 : 0.18) }
}

private struct GlassThemeKey: EnvironmentKey {
    static let defaultValue = GlassTheme(tint: .ocean, intensity: .balanced, useLiquidGlass: true, scheme: .light)
}

extension EnvironmentValues {
    var glass: GlassTheme {
        get { self[GlassThemeKey.self] }
        set { self[GlassThemeKey.self] = newValue }
    }
}

/// Injects a theme that follows the current colour scheme and preferences.
struct GlassThemeProvider: ViewModifier {
    @ObservedObject var services: AppServices
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let p = services.preferences
        content.environment(\.glass, GlassTheme(
            tint: p.glassTint, intensity: p.glassIntensity, useLiquidGlass: p.useLiquidGlass, scheme: scheme,
            customColor: p.glassCustomColor, transparency: p.glassTransparency
        ))
    }
}

// MARK: - Backdrop

/// Window background: behind-window blur of the desktop plus tinted light blobs.
struct GlassBackdrop: View {
    @Environment(\.glass) private var glass

    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            GeometryReader { proxy in
                let size = proxy.size
                let palette = glass.palette
                ZStack {
                    LinearGradient(
                        colors: [palette[0].opacity(glass.isDark ? 0.30 : 0.22), palette[1].opacity(glass.isDark ? 0.22 : 0.16)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Circle()
                        .fill(palette[0].opacity(glass.isDark ? 0.55 : 0.45))
                        .frame(width: size.width * 0.55, height: size.width * 0.55)
                        .blur(radius: 110)
                        .position(x: size.width * 0.12, y: size.height * 0.10)
                    Circle()
                        .fill(palette[1].opacity(glass.isDark ? 0.45 : 0.35))
                        .frame(width: size.width * 0.50, height: size.width * 0.50)
                        .blur(radius: 120)
                        .position(x: size.width * 0.92, y: size.height * 0.95)
                    Circle()
                        .fill(palette[2].opacity(glass.isDark ? 0.30 : 0.28))
                        .frame(width: size.width * 0.35, height: size.width * 0.35)
                        .blur(radius: 100)
                        .position(x: size.width * 0.65, y: size.height * 0.15)
                }
                .drawingGroup()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Panels

struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    var shadow: Bool
    @Environment(\.glass) private var glass

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .clipShape(shape)
            .background { GlassSurface(shape: shape) }
            .overlay { shape.strokeBorder(glass.borderGradient, lineWidth: 1).allowsHitTesting(false) }
            .compositingGroup()
            .shadow(color: shadow ? glass.shadow : .clear, radius: 18, x: 0, y: 8)
    }
}

/// Frosted fill. Uses the system Liquid Glass on macOS 26 when enabled and when built
/// with an SDK that provides it; otherwise a SwiftUI material plus a milky wash.
struct GlassSurface<S: Shape>: View {
    let shape: S
    @Environment(\.glass) private var glass

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), glass.useLiquidGlass {
            Color.clear.glassEffect(.regular, in: shape)
                .opacity(glass.panelOpacity)
        } else {
            materialFill
        }
        #else
        materialFill
        #endif
    }

    private var materialFill: some View {
        ZStack {
            shape.fill(glass.panelMaterial)
            shape.fill(glass.panelWash)
            // Specular highlight along the top edge.
            shape.fill(LinearGradient(colors: [.white.opacity(glass.isDark ? 0.06 : 0.30), .clear], startPoint: .top, endPoint: .center))
        }
        .opacity(glass.panelOpacity)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 16, shadow: Bool = true) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, shadow: shadow))
    }
}

// MARK: - Controls

/// Icon button with glass hover/press states. `isOn` renders an accent fill.
struct GlassIconButtonStyle: ButtonStyle {
    var isOn = false
    var size = CGSize(width: 30, height: 28)

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, isOn: isOn, size: size)
    }

    private struct GlassButtonBody: View {
        let configuration: Configuration
        let isOn: Bool
        let size: CGSize
        @State private var hovering = false
        @Environment(\.glass) private var glass
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(minWidth: size.width, minHeight: size.height)
                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(background)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var background: AnyShapeStyle {
            if isOn { return AnyShapeStyle(glass.selectionFill) }
            if configuration.isPressed { return AnyShapeStyle(glass.controlPressed) }
            if hovering && isEnabled { return AnyShapeStyle(glass.controlHover) }
            return AnyShapeStyle(Color.clear)
        }
    }
}

/// A capsule that groups related buttons, like the toolbar segments in the design.
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.glass) private var glass

    var body: some View {
        HStack(spacing: 2) { content }
            .padding(3)
            .background {
                Capsule(style: .continuous).fill(glass.controlFill)
            }
            .overlay {
                Capsule(style: .continuous).strokeBorder(glass.borderGradient, lineWidth: 0.75)
            }
    }
}

/// Text button with a glass capsule.
struct GlassCapsuleButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        CapsuleBody(configuration: configuration, prominent: prominent)
    }

    private struct CapsuleBody: View {
        let configuration: Configuration
        let prominent: Bool
        @State private var hovering = false
        @Environment(\.glass) private var glass

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background {
                    Capsule(style: .continuous).fill(prominent ? AnyShapeStyle(glass.selectionFill)
                        : AnyShapeStyle(configuration.isPressed ? glass.controlPressed : (hovering ? glass.controlHover : glass.controlFill)))
                }
                .overlay { Capsule(style: .continuous).strokeBorder(glass.borderGradient, lineWidth: 0.75) }
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - AppKit bridges

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

/// Gives SwiftUI access to the hosting NSWindow.
struct WindowAccessor: NSViewRepresentable {
    var configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowObservingView()
        view.onWindow = configure
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class WindowObservingView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}

/// Empty toolbar area that still drags the window (the title bar is hidden).
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        private var mouseDownEvent: NSEvent?

        // We drive the drag ourselves so a double-click is delivered intact.
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                mouseDownEvent = nil
                // zoom(_:) toggles between full size and the previous size even
                // though the hidden title bar leaves the zoom button disabled.
                window?.zoom(nil)
            } else {
                mouseDownEvent = event
            }
        }

        // Starting the drag only once the mouse moves keeps a plain click from
        // entering the window-drag loop, which would swallow the second click.
        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownEvent else { return }
            mouseDownEvent = nil
            window?.performDrag(with: start)
        }

        override func mouseUp(with event: NSEvent) {
            mouseDownEvent = nil
        }
    }
}

/// Makes the window translucent so the backdrop blur shows the desktop.
enum GlassWindowConfigurator {
    static func configure(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.tabbingMode = .disallowed
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 820, height: 480)
        window.toolbar = nil
    }
}
