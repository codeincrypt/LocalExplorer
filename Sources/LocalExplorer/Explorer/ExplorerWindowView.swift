import AppKit
import SwiftUI
import ExplorerCore

/// Window layout: glass backdrop, floating sidebar, toolbar, tab strip, file panel,
/// optional preview pane and status bar.
struct ExplorerWindowView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: TabModel
    @EnvironmentObject private var services: AppServices
    @FocusState private var focus: FocusTarget?
    @Environment(\.glass) private var glass

    var body: some View {
        ZStack {
            GlassBackdrop()
            HStack(spacing: 0) {
                if model.showSidebar {
                    SidebarView(model: model, tab: tab, services: services, volumes: services.volumes)
                        .frame(width: CGFloat(services.preferences.sidebarWidth))
                        .glassPanel()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    PaneResizeHandle(width: Binding(
                        get: { services.preferences.sidebarWidth },
                        set: { services.preferences.sidebarWidth = $0 }
                    ), range: 170...380, growsRight: true)
                }
                VStack(spacing: 8) {
                    ExplorerToolbar(model: model, tab: tab, focus: $focus)
                        // Keep clear of the traffic-light buttons when the sidebar is hidden.
                        .padding(.leading, model.showSidebar ? 0 : 70)
                    TabStrip(model: model)
                    HStack(spacing: 0) {
                        FileBrowserView(model: model, tab: tab, focus: $focus)
                            .glassPanel()
                            .swipeNavigation(
                                onBack: { if tab.history.canGoBack { tab.goBack() } },
                                onForward: { if tab.history.canGoForward { tab.goForward() } }
                            )
                        if model.showPreviewPane {
                            PaneResizeHandle(width: Binding(
                                get: { services.preferences.previewPaneWidth },
                                set: { services.preferences.previewPaneWidth = $0 }
                            ), range: 240...520, growsRight: false)
                            InspectorView(model: model, tab: tab, services: services)
                                .frame(width: CGFloat(services.preferences.previewPaneWidth))
                                .glassPanel()
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    StatusBar(model: model, tab: tab, services: services)
                }
            }
            .padding(8)
            if model.isShowingPhotoViewer {
                PhotoViewer(model: model, tab: tab, services: services)
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.isShowingPhotoViewer)
        .animation(.easeOut(duration: 0.18), value: model.showSidebar)
        .animation(.easeOut(duration: 0.18), value: model.showPreviewPane)
        .frame(minWidth: 820, minHeight: 480)
        .onAppear {
            tab.start()
            focus = .fileList
        }
        .onChange(of: model.focusRequest) { _, request in focus = request.target }
        .onChange(of: model.activeTabID) { _, _ in focus = .fileList }
        .sheet(item: $model.renameTarget) { item in
            RenameSheet(item: item, model: model)
        }
        .sheet(item: $model.conflictPrompt) { prompt in
            ConflictSheet(prompt: prompt)
        }
        .sheet(item: $model.batchRename) { request in
            BatchRenameSheet(request: request, model: model)
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { model.deleteConfirmation != nil }, set: { if !$0 { model.deleteConfirmation = nil } }),
            presenting: model.deleteConfirmation
        ) { confirmation in
            Button("Delete Immediately", role: .destructive) { model.confirmDeletePermanently(confirmation.urls) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can’t be undone. The items will not be moved to the Trash.")
        }
        .alert(
            model.errorAlert?.title ?? "",
            isPresented: Binding(get: { model.errorAlert != nil }, set: { if !$0 { model.errorAlert = nil } }),
            presenting: model.errorAlert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    private var deleteTitle: String {
        guard let urls = model.deleteConfirmation?.urls else { return "" }
        return urls.count == 1
            ? "Delete “\(urls[0].lastPathComponent)” immediately?"
            : "Delete \(urls.count) items immediately?"
    }
}

/// Thin draggable gap between panels for resizing the sidebar and preview pane.
struct PaneResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    /// True when dragging right makes the pane wider (sidebar).
    let growsRight: Bool
    @State private var startWidth: Double?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(hovering ? 0.35 : 0))
            .frame(width: 2)
            .padding(.horizontal, 3)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                // Global coordinates: the handle itself moves while dragging.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = startWidth ?? width
                        startWidth = start
                        let delta = Double(value.translation.width) * (growsRight ? 1 : -1)
                        width = min(max(start + delta, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .accessibilityHidden(true)
    }
}
