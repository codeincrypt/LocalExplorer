import AppKit
import SwiftUI
import ExplorerCore

/// Glass container for sheets.
struct GlassSheet<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content
    @Environment(\.glass) private var glass

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(glass.softSelectionFill))
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            content
        }
        .padding(20)
        .background { GlassSurface(shape: Rectangle()) }
    }
}

// MARK: - Rename

struct RenameSheet: View {
    let item: FileItem
    let model: WindowModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var confirmExtensionChange = false
    @FocusState private var focused: Bool
    @Environment(\.glass) private var glass

    init(item: FileItem, model: WindowModel) {
        self.item = item
        self.model = model
        _name = State(initialValue: item.name)
    }

    private var validation: FilenameValidation {
        let folder = item.url.deletingLastPathComponent()
        return FilenameValidator.validateRename(original: item.name, proposed: name, isDirectory: item.isDirectory && !item.isPackage) {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    var body: some View {
        GlassSheet(title: "Rename", symbol: "pencil") {
            HStack(spacing: 10) {
                Image(nsImage: FileIconProvider.icon(for: item)).resizable().frame(width: 32, height: 32)
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(submit)
                    .frame(minWidth: 320)
                    .accessibilityLabel("New name")
            }
            ForEach(Array(validation.issues.enumerated()), id: \.offset) { _, issue in
                Label(issue.message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.system(size: 11))
            }
            ForEach(Array(validation.warnings.enumerated()), id: \.offset) { _, warning in
                Label(warning.message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 11))
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!validation.isValid || name == item.name)
            }
        }
        .frame(width: 440)
        .onAppear { focused = true }
        .confirmationDialog("Change the extension?", isPresented: $confirmExtensionChange) {
            Button("Use “.\(FilenameParts(name: name).ext)”") { commit() }
            Button("Keep “.\(FilenameParts(name: item.name).ext)”") {
                name = FilenameParts(name: name).stem + (FilenameParts(name: item.name).ext.isEmpty ? "" : "." + FilenameParts(name: item.name).ext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("If you change the extension, “\(item.name)” may open in a different app.")
        }
    }

    private func submit() {
        guard validation.isValid, name != item.name else { return }
        if validation.warnings.contains(where: { if case .extensionChanged = $0 { return true } else { return false } }) {
            confirmExtensionChange = true
        } else {
            commit()
        }
    }

    private func commit() {
        model.rename(item, to: name)
        dismiss()
    }
}

// MARK: - Conflicts

struct ConflictSheet: View {
    let prompt: ConflictPrompt
    @State private var applyToAll = false
    @Environment(\.glass) private var glass

    private var conflict: FileConflict { prompt.conflict }

    var body: some View {
        GlassSheet(title: "An item named “\(conflict.existing.lastPathComponent)” already exists", symbol: "doc.on.doc") {
            Text("in “\(conflict.existing.deletingLastPathComponent().lastPathComponent)”. Choose what to do with the item you are \(conflict.operation == .move ? "moving" : "copying").")
                .font(.system(size: 12))
                .foregroundStyle(glass.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                ItemSummary(title: "Existing", url: conflict.existing)
                ItemSummary(title: conflict.operation == .move ? "Moving" : "Copying", url: conflict.source)
            }
            Text("Replace moves the existing item to the Trash.")
                .font(.system(size: 11))
                .foregroundStyle(glass.secondaryText)
            if conflict.remainingItems > 0 {
                Toggle("Apply to the remaining \(conflict.remainingItems) item\(conflict.remainingItems == 1 ? "" : "s")", isOn: $applyToAll)
                    .font(.system(size: 12))
            }
            HStack {
                Button("Cancel", role: .cancel) { respond(.cancel) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Skip") { respond(.skip) }
                Button("Keep Both") { respond(.keepBoth) }
                    .keyboardShortcut(.defaultAction)
                Button("Replace", role: .destructive) { respond(.replace) }
            }
        }
        .frame(width: 520)
        .onDisappear { prompt.respond(ConflictResolution(.cancel)) }
    }

    private func respond(_ action: ConflictAction) {
        prompt.respond(ConflictResolution(action, applyToRemaining: applyToAll))
    }

    private struct ItemSummary: View {
        let title: String
        let url: URL
        @Environment(\.glass) private var glass

        var body: some View {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey])
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(glass.secondaryText)
                HStack(spacing: 8) {
                    Image(nsImage: FileIconProvider.icon(forPath: url.path)).resizable().frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        if let date = values?.contentModificationDate {
                            Text("Modified \(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(glass.secondaryText)
                        }
                        if values?.isDirectory != true, let size = values?.fileSize {
                            Text(DisplayFormat.byteCount(Int64(size))).font(.system(size: 10)).foregroundStyle(glass.secondaryText)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(glass.controlFill))
        }
    }
}

// MARK: - Batch rename

struct BatchRenameSheet: View {
    let request: BatchRenameRequest
    let model: WindowModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.glass) private var glass

    enum Mode: String, CaseIterable, Identifiable {
        case replace = "Replace Text", add = "Add Text", format = "Format", changeCase = "Change Case"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .replace
    @State private var find = ""
    @State private var replacement = ""
    @State private var caseSensitive = false
    @State private var addition = ""
    @State private var position: BatchRenameRule.TextPosition = .after
    @State private var baseName = "Name "
    @State private var startIndex = 1
    @State private var digits = 2
    @State private var caseStyle: BatchRenameRule.CaseStyle = .lower

    private var rule: BatchRenameRule {
        switch mode {
        case .replace: return .replaceText(find: find, replacement: replacement, caseSensitive: caseSensitive)
        case .add: return .addText(addition, position: position)
        case .format: return .format(baseName: baseName, startIndex: startIndex, digits: digits, position: position)
        case .changeCase: return .changeCase(caseStyle)
        }
    }

    private var plan: [BatchRenameEntry] {
        BatchRenamePlanner.plan(for: request.urls, rule: rule, isDirectory: { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])).map { $0.isDirectory == true && $0.isPackage != true } ?? false
        })
    }

    var body: some View {
        let plan = self.plan
        let hasIssues = plan.contains { $0.issue != nil }
        let changes = plan.filter(\.isChange).count
        GlassSheet(title: "Rename \(request.urls.count) Items", symbol: "character.cursor.ibeam") {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch mode {
                case .replace:
                    TextField("Find", text: $find)
                    TextField("Replace with", text: $replacement)
                    Toggle("Case sensitive", isOn: $caseSensitive)
                case .add:
                    TextField("Text", text: $addition)
                    positionPicker
                case .format:
                    TextField("Custom format", text: $baseName)
                    Stepper("Start numbers at \(startIndex)", value: $startIndex, in: 0...999_999)
                    Stepper("Digits: \(digits)", value: $digits, in: 1...8)
                    positionPicker
                case .changeCase:
                    Picker("Case", selection: $caseStyle) {
                        Text("lowercase").tag(BatchRenameRule.CaseStyle.lower)
                        Text("UPPERCASE").tag(BatchRenameRule.CaseStyle.upper)
                        Text("Title Case").tag(BatchRenameRule.CaseStyle.title)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .textFieldStyle(.roundedBorder)

            Text("Preview").font(.system(size: 11, weight: .semibold)).foregroundStyle(glass.secondaryText)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plan) { entry in
                        HStack(spacing: 6) {
                            Text(entry.source.lastPathComponent).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(glass.secondaryText)
                            Text(entry.newName).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(entry.issue != nil ? Color.red : (entry.isChange ? Color.primary : glass.secondaryText))
                                .help(entry.issue?.message ?? "")
                        }
                        .font(.system(size: 11))
                    }
                }
                .padding(8)
            }
            .frame(height: 180)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(glass.controlFill))

            if let issue = plan.first(where: { $0.issue != nil })?.issue {
                Label(issue.message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.system(size: 11))
            }
            HStack {
                Text("\(changes) of \(plan.count) names change").font(.system(size: 11)).foregroundStyle(glass.secondaryText)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename") {
                    model.applyBatchRename(plan)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(hasIssues || changes == 0)
            }
        }
        .frame(width: 560)
    }

    private var positionPicker: some View {
        Picker("Where", selection: $position) {
            Text("Before name").tag(BatchRenameRule.TextPosition.before)
            Text("After name").tag(BatchRenameRule.TextPosition.after)
        }
        .pickerStyle(.segmented)
    }
}
