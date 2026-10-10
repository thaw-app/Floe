//
//  FieldEditorViews.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

// MARK: Manifest fields (preferences and arguments)

/// One preference or argument from a manifest, edited as text ("true"/"false" for checkboxes).
struct FieldEditor: View {
    let field: FieldSpec
    @Binding var value: String

    var body: some View {
        Group {
            switch field.type {
            case "checkbox":
                CheckboxHeading(text: field.checkbox.heading)
                Toggle(field.checkbox.text, isOn: Binding(get: { value == "true" }, set: { value = $0 ? "true" : "false" }))
            case "dropdown":
                Picker(selection: $value) {
                    ForEach(field.options, id: \.value) { Text($0.title).tag($0.value) }
                } label: { label }
            case "password":
                SecureField(text: $value, prompt: field.placeholder.map { Text($0) }) { label }
            case "appPicker":
                AppPickerField(value: $value, required: field.required) { label }
            case "file", "directory":
                LabeledContent {
                    HStack {
                        Text(value.isEmpty ? String(localized: "None", bundle: .floe, comment: "Shown where a file or folder would be, when none is chosen.") : (value as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(value.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") {
                            if let path = ModalGuard.choosePaths(directories: field.type == "directory", multiple: false).first {
                                value = path
                            }
                        }
                    }
                } label: { label }
            default:
                TextField(text: $value, prompt: field.placeholder.map { Text($0) }) { label }
            }
        }
        .help(field.detail ?? "")
    }

    private var label: some View {
        Text(field.required ? "\(field.title) *" : field.title)
    }
}

/// The title a checkbox starts a group with, on a line of its own over the group.
struct CheckboxHeading: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
        }
    }
}

/// Asks for a command's required preferences or its arguments before it runs.
struct SetupView: View {
    @ObservedObject var form: SetupFormModel
    let request: SetupRequest
    @FocusState private var focusedField: String?

    var body: some View {
        let command = request.command
        VStack(spacing: 0) {
            PanelHeader(
                title: request.kind == .preferences ? String(localized: "Set Up \(command.extensionTitle)", bundle: .floe, comment: "A heading. The placeholder is an extension's name.") : command.title,
                icon: command.icon,
                assetsPath: command.assetsPath
            )
            Form {
                Section {
                    ForEach(request.fields) { field in
                        FieldEditor(field: field, value: Binding(
                            get: { form.values[field.name] ?? "" },
                            set: { form.values[field.name] = $0 }
                        ))
                        .focused($focusedField, equals: field.name)
                    }
                } footer: {
                    Text(request.kind == .preferences
                        ? "\(command.extensionTitle) needs these before it can run. Change them later in Floe Settings."
                        : "Arguments for \(command.title).")
                        .font(ThawType.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            Footer(primary: request.kind == .preferences ? String(localized: "Save and Continue", bundle: .floe) : String(localized: "Run Command", bundle: .floe)) {
                if let error = form.error {
                    Text(error).foregroundStyle(.red).lineLimit(1)
                } else {
                    Text("Esc to cancel").foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { focusedField = request.fields.first { $0.type != "checkbox" }?.name }
    }
}

/// An app picker: installed apps with icons, Other… for anything else, and None when it isn't required.
/// The value is the app's path; a default given by bundle id or name shows as the app it names.
struct AppPickerField<Title: View>: View {
    @Binding var value: String
    let required: Bool
    @ViewBuilder let label: Title
    @State private var apps: [AppPickerValue.App] = []

    private var chosen: AppPickerValue.App? {
        AppPickerValue.match(value, in: apps) ?? (value.hasSuffix(".app") ? AppPickerValue.App(
            name: ((value as NSString).lastPathComponent as NSString).deletingPathExtension, path: value, bundleId: nil
        ) : nil)
    }

    var body: some View {
        LabeledContent {
            Menu {
                if !required {
                    Button("None") { value = "" }
                    Divider()
                }
                ForEach(apps, id: \.path) { app in
                    Button {
                        value = app.path
                    } label: {
                        Label { Text(app.name) } icon: { Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)) }
                    }
                }
                Divider()
                Button("Other…") {
                    if let path = ModalGuard.chooseApp() {
                        value = path
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if let chosen {
                        AppIconView(path: chosen.path, size: 16)
                        Text(chosen.name)
                    } else {
                        Text("Choose an App").foregroundStyle(.secondary)
                    }
                }
            }
            .fixedSize()
            .accessibilityLabel(chosen?.name ?? String(localized: "not set", bundle: .floe, comment: "Read aloud for an app picker with no app chosen."))
        } label: { label }
            .task {
                apps = InstalledApps.list()
                // Show a default given by bundle id or name as the app's path, so it saves the same way.
                if let match = AppPickerValue.match(value, in: apps), match.path != value {
                    value = match.path
                }
            }
    }
}
