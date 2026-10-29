import AppKit
import PDFKit
import SwiftUI
import ExplorerCore

struct PDFPreviewProvider: PreviewProvider {
    let kind = PreviewKind.pdf
    func makeView(_ context: PreviewContext) -> AnyView {
        AnyView(PDFPreview(item: context.item, style: context.style, open: context.open))
    }
}

enum PDFLayout: String, CaseIterable, Identifiable {
    case single = "Single Page", continuous = "Continuous", twoUp = "Two Pages"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .single: return "doc"
        case .continuous: return "doc.text"
        case .twoUp: return "book"
        }
    }
    var mode: PDFDisplayMode {
        switch self {
        case .single: return .singlePage
        case .continuous: return .singlePageContinuous
        case .twoUp: return .twoUpContinuous
        }
    }
}

/// Owns the PDFView (and thumbnail strip) for one document. PDFKit loads pages lazily,
/// so large documents stay responsive; the document is released with the controller.
@MainActor
final class PDFViewerController: ObservableObject {
    let pdfView = PDFView()
    let thumbnails = PDFThumbnailView()
    @Published private(set) var pageIndex = 0
    @Published private(set) var pageCount = 0
    @Published var layout: PDFLayout = .continuous { didSet { pdfView.displayMode = layout.mode } }
    @Published private(set) var matches: [PDFSelection] = []
    @Published private(set) var matchIndex = 0
    @Published private(set) var isLocked = false
    @Published private(set) var fitsWidth = true
    private var observers: [NSObjectProtocol] = []

    init() {
        pdfView.autoScales = true
        pdfView.displayMode = layout.mode
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .clear
        pdfView.pageShadowsEnabled = true
        thumbnails.pdfView = pdfView
        thumbnails.thumbnailSize = CGSize(width: 72, height: 96)
        thumbnails.backgroundColor = .clear
        observers.append(NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncPage() }
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func setDocument(_ document: PDFDocument) {
        isLocked = document.isLocked
        pdfView.document = document
        pageCount = document.pageCount
        syncPage()
    }

    func unlock(_ password: String) -> Bool {
        guard let document = pdfView.document, document.unlock(withPassword: password) else { return false }
        // Re-assign so PDFView lays out the now-readable pages.
        pdfView.document = nil
        setDocument(document)
        return true
    }

    func release() {
        pdfView.document = nil
        thumbnails.pdfView = nil
    }

    private func syncPage() {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return }
        pageIndex = document.index(for: page)
        pageCount = document.pageCount
    }

    func goToPreviousPage() { if pdfView.canGoToPreviousPage { pdfView.goToPreviousPage(nil) } }
    func goToNextPage() { if pdfView.canGoToNextPage { pdfView.goToNextPage(nil) } }

    func go(toPage number: Int) {
        guard let document = pdfView.document, number >= 1, number <= document.pageCount,
              let page = document.page(at: number - 1) else { return }
        pdfView.go(to: page)
    }

    func zoomIn() { pdfView.autoScales = false; fitsWidth = false; pdfView.zoomIn(nil) }
    func zoomOut() { pdfView.autoScales = false; fitsWidth = false; pdfView.zoomOut(nil) }
    func fitWidth() { pdfView.autoScales = true; fitsWidth = true }

    /// Case-insensitive search across the document; highlights all matches and jumps
    /// to the first. Searching runs on the main actor but PDFKit returns quickly for
    /// typical documents; very large documents may take a moment.
    func search(_ text: String) {
        guard let document = pdfView.document else { return }
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            matches = []
            pdfView.highlightedSelections = nil
            return
        }
        matches = document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
        for match in matches { match.color = NSColor.systemYellow.withAlphaComponent(0.5) }
        pdfView.highlightedSelections = matches
        matchIndex = 0
        showMatch()
    }

    func nextMatch(_ step: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + step + matches.count) % matches.count
        showMatch()
    }

    private func showMatch() {
        guard matches.indices.contains(matchIndex) else { return }
        let selection = matches[matchIndex]
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.go(to: selection)
    }
}

private struct PDFPreview: View {
    let item: FileItem
    let style: PreviewStyle
    let open: () -> Void
    @StateObject private var controller = PDFViewerController()
    @State private var loaded = false
    @State private var failed = false
    @State private var showThumbnails = false
    @State private var query = ""
    @State private var password = ""
    @State private var wrongPassword = false
    @State private var pageField = ""
    @Environment(\.glass) private var glass

    var body: some View {
        VStack(spacing: 0) {
            if failed {
                PreviewMessageView(item: item, title: "This PDF can’t be opened", message: "The file may be damaged or not a valid PDF document.", open: open, compact: style == .compact)
            } else if controller.isLocked {
                lockedView
            } else {
                if style == .full && loaded { toolbar.padding(.vertical, 6) }
                HStack(spacing: 0) {
                    if style == .full && showThumbnails {
                        PDFThumbnailRepresentable(view: controller.thumbnails)
                            .frame(width: 100)
                        Rectangle().fill(glass.hairline).frame(width: 1)
                    }
                    PDFViewRepresentable(view: controller.pdfView)
                        .accessibilityLabel("PDF preview of \(item.name)")
                }
                if style == .compact && loaded && controller.pageCount > 0 {
                    Text("Page \(controller.pageIndex + 1) of \(controller.pageCount)")
                        .font(.system(size: 10))
                        .foregroundStyle(glass.secondaryText)
                        .padding(.top, 4)
                }
            }
        }
        .overlay { if !loaded && !failed { ProgressView().controlSize(.small) } }
        .task(id: item.id) { await load() }
        .onDisappear { controller.release() }
    }

    private func load() async {
        let url = item.url
        let box = await Task.detached(priority: .userInitiated) {
            PDFDocument(url: url).map { UncheckedBox(value: $0) }
        }.value
        guard !Task.isCancelled else { return }
        if let document = box?.value {
            if style == .compact { controller.layout = .single }
            controller.setDocument(document)
            loaded = true
        } else {
            failed = true
        }
    }

    private var toolbar: some View {
        PreviewControlBar {
            PreviewButton(symbol: "sidebar.left", label: "Thumbnails", isOn: showThumbnails) { showThumbnails.toggle() }
            Menu {
                Picker("Layout", selection: $controller.layout) {
                    ForEach(PDFLayout.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: controller.layout.symbol)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 4)
            .help("Page layout")
            Divider().frame(height: 16)
            PreviewButton(symbol: "chevron.up", label: "Previous Page") { controller.goToPreviousPage() }
            TextField("", text: $pageField, prompt: Text("\(controller.pageIndex + 1)"))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 11).monospacedDigit())
                .frame(width: 30)
                .onSubmit {
                    if let number = Int(pageField) { controller.go(toPage: number) }
                    pageField = ""
                }
                .accessibilityLabel("Page number")
            Text("/ \(controller.pageCount)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(glass.secondaryText)
            PreviewButton(symbol: "chevron.down", label: "Next Page") { controller.goToNextPage() }
            Divider().frame(height: 16)
            PreviewButton(symbol: "minus.magnifyingglass", label: "Zoom Out") { controller.zoomOut() }
            PreviewButton(symbol: "plus.magnifyingglass", label: "Zoom In") { controller.zoomIn() }
            PreviewButton(symbol: "arrow.left.and.right", label: "Fit Width", isOn: controller.fitsWidth) { controller.fitWidth() }
            Divider().frame(height: 16)
            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(glass.secondaryText)
            TextField("Find in PDF", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 110)
                .onSubmit { controller.search(query) }
                .accessibilityLabel("Find in PDF")
            if !controller.matches.isEmpty {
                Text("\(controller.matchIndex + 1)/\(controller.matches.count)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(glass.secondaryText)
                PreviewButton(symbol: "chevron.left", label: "Previous Match") { controller.nextMatch(-1) }
                PreviewButton(symbol: "chevron.right", label: "Next Match") { controller.nextMatch(1) }
            } else if !query.isEmpty {
                Text("Return to search").font(.system(size: 10)).foregroundStyle(glass.secondaryText)
            }
        }
    }

    private var lockedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.doc")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(glass.secondaryText)
            Text("This PDF is password-protected").font(.system(size: 13, weight: .semibold))
            if style == .full {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit {
                        wrongPassword = !controller.unlock(password)
                        password = ""
                    }
                if wrongPassword {
                    Text("Incorrect password").font(.system(size: 11)).foregroundStyle(.red)
                }
            } else {
                Text("Open it in Gallery view (⌘3) to enter the password.")
                    .font(.system(size: 11))
                    .foregroundStyle(glass.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PDFViewRepresentable: NSViewRepresentable {
    let view: PDFView
    func makeNSView(context: Context) -> PDFView { view }
    func updateNSView(_ nsView: PDFView, context: Context) {}
}

struct PDFThumbnailRepresentable: NSViewRepresentable {
    let view: PDFThumbnailView
    func makeNSView(context: Context) -> PDFThumbnailView { view }
    func updateNSView(_ nsView: PDFThumbnailView, context: Context) {}
}
