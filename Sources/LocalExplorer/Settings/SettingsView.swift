import AppKit
import SwiftUI
import ExplorerCore

struct SettingsView: View {
    @EnvironmentObject private var services: AppServices

    var body: some View {
        TabView {
            GeneralSettings(services: services)
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings(services: services)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            AccessSettings(services: services)
                .tabItem { Label("Access", systemImage: "lock.shield") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            PrivacySettings(services: services)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 560, height: 540)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var services: AppServices

    var body: some View {
        Form {
            Picker("Default view", selection: $services.state.preferences.defaultViewMode) {
                ForEach(ViewMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Sort by", selection: $services.state.preferences.sort.key) {
                ForEach(FileSortKey.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Ascending", isOn: $services.state.preferences.sort.ascending)
            Toggle("Keep folders on top", isOn: $services.state.preferences.sort.directoriesFirst)
            Toggle("Show hidden files", isOn: $services.state.preferences.showHiddenFiles)
            Toggle("Reopen tabs from last session", isOn: $services.state.preferences.restoreTabs)
            LabeledContent("New tabs open") {
                HStack {
                    Text(services.preferences.startPath ?? "Home folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url {
                            services.preferences.startPath = url.path
                        }
                    }
                    if services.preferences.startPath != nil {
                        Button("Reset") { services.preferences.startPath = nil }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @ObservedObject var services: AppServices

    /// Shows the custom colour; choosing one switches the tint to Custom.
    private var glassColor: Binding<Color> {
        Binding(
            get: {
                let c = services.preferences.glassCustomColor
                return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
            },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                services.state.preferences.glassCustomColor = GlassColor(
                    red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent)
                )
                services.state.preferences.glassTint = .custom
            }
        )
    }

    var body: some View {
        Form {
            Picker("Appearance", selection: Binding(
                get: { services.preferences.appearance },
                set: { services.preferences.appearance = $0; services.applyAppearance() }
            )) {
                ForEach(AppearanceMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Glass tint", selection: $services.state.preferences.glassTint) {
                ForEach(GlassTint.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            ColorPicker("Glass color", selection: glassColor, supportsOpacity: false)
            Picker("Glass intensity", selection: $services.state.preferences.glassIntensity) {
                ForEach(GlassIntensity.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledContent("Glass transparency") {
                HStack {
                    Slider(value: $services.state.preferences.glassTransparency, in: 0...AppPreferences.maxGlassTransparency)
                    Text(services.preferences.glassTransparency, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .accessibilityElement(children: .combine)
            Toggle("Use Liquid Glass on macOS 26 and later", isOn: $services.state.preferences.useLiquidGlass)
            LabeledContent("Icon size") {
                Slider(value: $services.state.preferences.tileSize, in: 64...256)
            }
            Section {
                GlassPreview()
                    .frame(height: 120)
                    .listRowInsets(EdgeInsets())
            }
        }
        .formStyle(.grouped)
    }
}

private struct GlassPreview: View {
    var body: some View {
        ZStack {
            GlassBackdrop()
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4).fill(.clear).frame(width: 90, height: 80).glassPanel(cornerRadius: 12)
                RoundedRectangle(cornerRadius: 4).fill(.clear).frame(height: 80).glassPanel(cornerRadius: 12)
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct AccessSettings: View {
    @ObservedObject var services: AppServices

    var body: some View {
        Form {
            Section("Authorized folders") {
                if services.state.authorizedLocations.isEmpty {
                    Text("No folders added. Local Explorer can browse anything your user account can read; add folders here when macOS asks for permission or when running a sandboxed build.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(services.state.authorizedLocations) { location in
                    HStack {
                        Image(systemName: services.unavailableLocationIDs.contains(location.id) ? "exclamationmark.triangle.fill" : "folder.fill")
                            .foregroundStyle(services.unavailableLocationIDs.contains(location.id) ? Color.orange : Color.accentColor)
                        VStack(alignment: .leading) {
                            Text(location.name)
                            Text(location.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("Remove") { services.removeAuthorizedLocation(location.id) }
                    }
                }
                Button("Grant Access to Folder…") { services.grantAccess() }
            }
            Section("Full Disk Access") {
                Text("Some locations (Mail, Messages, Safari data, other users' folders, Time Machine) are protected by macOS. To browse them, add \(AppConfiguration.productName) under System Settings › Privacy & Security › Full Disk Access, then relaunch. The app cannot grant this permission to itself, and System Integrity Protection still blocks system files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Full Disk Access Settings") { AccessManager.openFullDiskAccessSettings() }
                LabeledContent("Sandboxed build", value: AccessManager.isSandboxed ? "Yes" : "No")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutSettings: View {
    var body: some View {
        List {
            ForEach(CommandCategory.allCases, id: \.self) { category in
                Section(category.rawValue.capitalized) {
                    ForEach(ExplorerCommand.allCases.filter { $0.category == category && $0.shortcut != nil }, id: \.self) { command in
                        HStack {
                            Label(command.title, systemImage: command.symbolName)
                            Spacer()
                            Text(command.shortcut?.displayString ?? "")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if command.shortcutScope == .fileList {
                                Text("file list").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            Section("Not bound") {
                Text("Delete Immediately has no shortcut on purpose; use File › Delete Immediately… and confirm.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PrivacySettings: View {
    @ObservedObject var services: AppServices

    var body: some View {
        Form {
            Section("Offline by design") {
                Text("\(AppConfiguration.productName) works entirely on this Mac. It has no account, no cloud sync, no analytics or telemetry and makes no network requests for browsing, previews, search or file operations.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Stored data") {
                LabeledContent("Settings file") {
                    Text(services.store.fileURL.path).font(.caption).textSelection(.enabled).lineLimit(2)
                }
                LabeledContent("Recent folders", value: "\(services.state.recents.paths.count)")
                Button("Clear Recent Folders") { services.clearRecents() }
                Stepper("Thumbnail cache limit: \(services.preferences.thumbnailCacheLimitMB) MB",
                        value: Binding(get: { services.preferences.thumbnailCacheLimitMB },
                                       set: { services.preferences.thumbnailCacheLimitMB = $0; services.thumbnails.setLimit(megabytes: $0) }),
                        in: 32...2048, step: 32)
                Button("Clear Thumbnail Cache") { services.thumbnails.clear() }
                Text("Thumbnails are kept in memory only and never include file contents on disk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
