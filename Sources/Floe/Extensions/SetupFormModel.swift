//
//  SetupFormModel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Fields to fill in before a command can run: its required preferences, or its arguments.
struct SetupRequest {
    enum Kind { case preferences, arguments }
    let command: ExtensionCommand
    let kind: Kind
    let fields: [FieldSpec]
}

/// What is typed into a setup form, and what is wrong with it. Which form is showing is the launcher model's.
final class SetupFormModel: ObservableObject {
    /// Field values for the form on screen, as text; checkboxes are "true" or "false".
    @Published var values: [String: String] = [:]
    @Published private(set) var error: String?

    /// Starts a form on what is stored for its fields, or on their defaults.
    func begin(_ request: SetupRequest) {
        var values: [String: String] = [:]
        for field in request.fields {
            let scope = request.command.commandPreferences.contains { $0.name == field.name } ? request.command : nil
            let stored = request.kind == .preferences
                ? PreferenceStore.value(field, extensionName: request.command.extensionName, command: scope)
                : nil
            values[field.name] = FieldValues.initialText(for: field, stored: stored)
        }
        self.values = values
        error = nil
    }

    /// The typed values once every required field is filled in. Otherwise nil, and `error` names what is missing.
    func validated(for request: SetupRequest) -> [String: Any]? {
        let missing = FieldValues.missing(request.fields, texts: values)
        guard missing.isEmpty else {
            error = String(localized: "Fill in \(missing.map(\.displayTitle).joined(separator: ", ")).", bundle: .floe, comment: "The placeholder is a list of the names of the fields left empty.")
            return nil
        }
        return FieldValues.typed(values, fields: request.fields)
    }
}
