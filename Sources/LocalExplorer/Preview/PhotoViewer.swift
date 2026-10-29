import AppKit
import SwiftUI
import ExplorerCore

/// In-window photo viewer. Covers the window; ← / → move through the photos of the
/// current folder, Esc closes. Zoom and rotate come from the shared image preview.
struct PhotoViewer: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: TabModel
    @ObservedObject var services: AppServices
    @FocusState private var focused: Bool
    @Environment(\.glass) private var glass

    private var photos: [FileItem] { tab.items.filter { $0.category == .image } }

    private var sequence: PhotoSequence {
        PhotoSequence(ids: photos.map(\.id), current: tab.focusedItem?.id)
    }

    var body: some View {
        let sequence = sequence
        let current = sequence.currentID.flatMap { id in photos.first { $0.id == id } }
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.62))
            if let current {
                PreviewHost(item: current, style: .full, services: services, open: { model.openExternally(current) })
                    .padding(.horizontal, 64)
                    .padding(.top, 48)
                    .padding(.bottom, 8)
            }
            HStack {
                stepButton("chevron.left", offset: -1, enabled: sequence.hasPrevious, in: sequence)
                Spacer()
                stepButton("chevron.right", offset: 1, enabled: sequence.hasNext, in: sequence)
            }
            .padding(.horizontal, 14)
            VStack {
                header(current, sequence: sequence)
                Spacer()
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(glass.borderGradient, lineWidth: 0.75) }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: [.down, .repeat]) { press in handle(press, sequence: sequence) }
        .onAppear { focused = true }
        // The photo can vanish (deleted elsewhere, folder changed): leave the viewer.
        .onChange(of: sequence.currentID) { _, id in if id == nil { model.closePhotoViewer() } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Photo viewer")
        .accessibilityIdentifier("photoViewer")
    }

    private func header(_ current: FileItem?, sequence: PhotoSequence) -> some View {
        HStack(spacing: 10) {
            Text(current?.name ?? "")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            if let position = sequence.positionDescription {
                Text(position).foregroundStyle(glass.secondaryText).monospacedDigit()
            }
            Spacer()
            Text("← → browse   Esc close").foregroundStyle(glass.secondaryText)
            Button { model.closePhotoViewer() } label: { Image(systemName: "xmark") }
                .buttonStyle(GlassIconButtonStyle(size: CGSize(width: 26, height: 24)))
                .help("Close (Esc)")
                .accessibilityLabel("Close photo viewer")
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private func stepButton(_ symbol: String, offset: Int, enabled: Bool, in sequence: PhotoSequence) -> some View {
        Button { step(offset, in: sequence) } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).frame(width: 34, height: 34)
        }
        .buttonStyle(GlassIconButtonStyle(size: CGSize(width: 34, height: 34)))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(offset < 0 ? "Previous photo" : "Next photo")
    }

    private func step(_ offset: Int, in sequence: PhotoSequence) {
        if let id = sequence.target(offset: offset) { show(id) }
    }

    private func show(_ id: String) {
        tab.selectionModel.click(id, order: tab.itemIDs)
    }

    private func handle(_ press: KeyPress, sequence: PhotoSequence) -> KeyPress.Result {
        guard press.modifiers.subtracting(.shift).isEmpty else { return .ignored }
        switch press.key {
        case .leftArrow, .upArrow:
            step(-1, in: sequence)
        case .rightArrow, .downArrow:
            step(1, in: sequence)
        case .home:
            if let id = sequence.first { show(id) }
        case .end:
            if let id = sequence.last { show(id) }
        case .escape:
            guard press.phase != .repeat else { return .handled }
            model.closePhotoViewer()
        default:
            return .ignored
        }
        return .handled
    }
}
