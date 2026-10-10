//
//  FormViews.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// Title row used in place of the search field when a view has nothing to search.
struct PanelHeader: View {
    let title: String
    let icon: String?
    let assetsPath: String
    var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: ThawSpacing.row) {
                IconView(value: icon ?? "icon:Terminal", assetsPath: assetsPath, size: 20)
                Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
            ZStack {
                Divider()
                if isLoading {
                    ProgressView().progressViewStyle(.linear).frame(height: 2)
                }
            }
            .frame(height: 2)
        }
    }
}

/// Keeps the launcher panel from hiding while a sheet such as NSOpenPanel has focus.
enum ModalGuard {
    private(set) static var isActive = false

    /// Asks for one application, starting in /Applications.
    static func chooseApp() -> String? {
        run {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.level = .modalPanel
            return panel.runModal() == .OK ? panel.url?.path : nil
        }
    }

    static func run<T>(_ body: () -> T) -> T {
        isActive = true
        defer {
            isActive = false
            NSApp.windows.first { $0 is LauncherPanel && $0.isVisible }?.makeKey()
        }
        return body()
    }

    static func choosePaths(directories: Bool, multiple: Bool) -> [String] {
        run {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = directories
            panel.canChooseFiles = !directories
            panel.allowsMultipleSelection = multiple
            panel.level = .modalPanel
            return panel.runModal() == .OK ? panel.urls.map(\.path) : []
        }
    }
}

// MARK: Extension forms

/// Renders a Raycast `<Form>`; values live in the session and go out with onChange and onSubmit.
struct FormBody: View {
    @ObservedObject var session: ExtensionSession
    let focusToken: Int
    @FocusState private var focusedField: Int?

    var body: some View {
        let fields = session.view?.content ?? []
        Form {
            ForEach(fields) { node in
                field(node)
                    .focused($focusedField, equals: node.id)
                if let error = node.string("error") {
                    Text(error).font(ThawType.footnote).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { focusFirst(fields) }
        .onChange(of: focusToken) { focusFirst(fields) }
    }

    private func focusFirst(_ fields: [Node]) {
        focusedField = fields.first { ["Form.TextField", "Form.PasswordField", "Form.TextArea"].contains($0.type) }?.id
    }

    private func text(_ node: Node) -> Binding<String> {
        Binding(get: { session.formValue(node) as? String ?? "" }, set: { session.setFormValue(node, $0) })
    }

    private func title(_ node: Node) -> String {
        node.string("title") ?? ""
    }

    @ViewBuilder
    private func field(_ node: Node) -> some View {
        switch node.type {
        case "Form.TextField":
            FormTypedRow(title: title(node)) {
                TextField(title(node), text: text(node), prompt: node.string("placeholder").map { Text($0) })
            }
            .help(node.string("info") ?? "")
        case "Form.PasswordField":
            FormTypedRow(title: title(node)) {
                SecureField(title(node), text: text(node), prompt: node.string("placeholder").map { Text($0) })
            }
        case "Form.TextArea":
            FormTextArea(title: title(node), text: text(node))
        case "Form.Checkbox":
            let checkbox = CheckboxText.parts(title: node.string("title"), label: node.string("label"))
            CheckboxHeading(text: checkbox.heading)
            Toggle(checkbox.text, isOn: Binding(get: { session.formValue(node) as? Bool ?? false }, set: { session.setFormValue(node, $0) }))
        case "Form.DatePicker":
            DatePicker(
                title(node),
                selection: date(node),
                displayedComponents: node.props["type"] as? String == "date" ? [.date] : [.date, .hourAndMinute]
            )
        default:
            pickerField(node)
        }
    }

    /// The fields that choose or only show something, apart from the ones that are typed into.
    @ViewBuilder
    private func pickerField(_ node: Node) -> some View {
        switch node.type {
        case "Form.Dropdown":
            let items = node.descendants(ofType: "Dropdown.Item")
            Picker(title(node), selection: text(node)) {
                ForEach(items) { item in Text(item.string("title") ?? "").tag(item.props["value"] as? String ?? "") }
            }
        case "Form.TagPicker":
            tagPicker(node)
        case "Form.FilePicker":
            filePicker(node)
        case "Form.Description":
            LabeledContent(title(node)) { Text(node.string("text") ?? "").foregroundStyle(.secondary) }
        case "Form.Separator":
            Divider()
        default:
            EmptyView()
        }
    }

    private func date(_ node: Node) -> Binding<Date> {
        Binding(
            get: {
                (session.formValue(node) as? String).flatMap { try? Date($0, strategy: .iso8601) } ?? Date()
            },
            set: { session.setFormValue(node, $0.formatted(.iso8601)) }
        )
    }

    private func tagPicker(_ node: Node) -> some View {
        let items = node.descendants(ofType: "Form.TagPicker.Item")
        let selected = session.formValue(node) as? [String] ?? []
        let titles = items.filter { selected.contains($0.props["value"] as? String ?? "") }.compactMap { $0.string("title") }
        return LabeledContent(title(node)) {
            Menu(titles.isEmpty ? (node.string("placeholder") ?? String(localized: "None", bundle: .floe, comment: "Shown where a file or folder would be, when none is chosen.")) : titles.joined(separator: ", ")) {
                ForEach(items) { item in
                    let value = item.props["value"] as? String ?? ""
                    Toggle(item.string("title") ?? value, isOn: Binding(
                        get: { selected.contains(value) },
                        set: { isOn in session.setFormValue(node, isOn ? selected + [value] : selected.filter { $0 != value }) }
                    ))
                }
            }
            .fixedSize()
        }
    }

    private func filePicker(_ node: Node) -> some View {
        let paths = session.formValue(node) as? [String] ?? []
        return LabeledContent(title(node)) {
            HStack {
                Text(paths.isEmpty ? String(localized: "None", bundle: .floe, comment: "Shown where a file or folder would be, when none is chosen.") : paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))
                    .foregroundStyle(paths.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Button("Choose…") {
                    let chosen = ModalGuard.choosePaths(
                        directories: node.bool("canChooseDirectories") && !node.bool("canChooseFiles"),
                        multiple: node.props["allowMultipleSelection"] as? Bool ?? true
                    )
                    if !chosen.isEmpty {
                        session.setFormValue(node, chosen)
                    }
                }
            }
        }
    }
}

/// A row of an extension's form that is typed into: the title at the side, and the field over the rest of the row.
/// As a row of its own, a grouped form sets a field's text against the trailing edge and gives a text area half the row.
struct FormTypedRow<Field: View>: View {
    let title: String
    var alignment: VerticalAlignment = .firstTextBaseline
    @ViewBuilder let field: Field

    var body: some View {
        HStack(alignment: alignment, spacing: ThawSpacing.row) {
            if !title.isEmpty {
                Text(title)
            }
            field
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity)
        }
    }
}

/// A form's text area: a box typed into from its top left.
struct FormTextArea: View {
    let title: String
    @Binding var text: String

    var body: some View {
        FormTypedRow(title: title, alignment: .top) {
            TextEditor(text: $text)
                .font(ThawType.body)
                .frame(minHeight: 80, maxHeight: 140)
                .scrollContentBackground(.hidden)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 6))
                .accessibilityLabel(title)
        }
    }
}
