//
//  ActionsSettingsSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The Commands page's Actions tab: for each kind of result, what Return does, and for each of Floe's rows of its
/// Actions menu, keys that run it and whether the menu shows it. What is offered and what is refused is decided in
/// ActionOptions.swift.
struct ActionsSettingsSection: View {
    @ObservedObject var settings: AppSettings
    var installed = AppLookup.system
    @State private var kind = SubjectKind.app
    /// Keys just refused, shown under the row they were recorded for.
    @State private var refusal: (row: ActionID, text: String)?

    /// The kind's rows, a role's named after the app it opens in now.
    private var options: [ActionOption] {
        ActionOption.rows(for: kind, roleApps: PreferredApps.apps(choice: settings.appChoice, installed: installed))
    }

    var body: some View {
        let options = options
        let results = String(localized: "Results", bundle: .floe, comment: "The label of the buttons that pick the kind of result whose actions are set: apps, files, folders or links.")
        ThawSection("Actions on Results") {
            LabeledContent {
                ThawPillPicker(selection: $kind, values: SubjectKind.allCases, title: \.title)
                    .accessibilityLabel(Text(results))
            } label: {
                Text(results)
            }
            ThawPicker(selection: returnChoice(among: options)) {
                Text(kind.floeActionTitle(browser: BrowserMenu(choice: settings.browserApp, installed: installed)))
                    .tag(ActionID?.none)
                ForEach(options.filter { !$0.isSubmenu }) { option in
                    Text(option.title).tag(ActionID?.some(option.id))
                }
            } label: {
                Text(String(localized: "Primary Action", bundle: .floe, comment: "The label of the picker that chooses what Return does on a result of this kind."))
                Text("Return runs it. Where it can't, such as Quit on an app that isn't running, Return opens the result instead.")
            }
        }
        .onChange(of: kind) { refusal = nil }
        ThawSection("Actions Menu") {
            Text("Keys run an action while a result of this kind is selected. Floe gives some actions keys, which you can change or clear; keys you choose need Command. An action left out of the menu keeps its keys.")
                .foregroundStyle(ThawInk.supporting)
            ForEach(options) { option in
                row(option, among: options)
                if let refusal, refusal.row == option.id {
                    Text(refusal.text).foregroundStyle(.red)
                }
            }
        }
        // A recorder listening when the kind changes stops, so the keys it records never land on another kind's rows.
        .id(kind)
    }

    private func row(_ option: ActionOption, among options: [ActionOption]) -> some View {
        LabeledContent {
            HStack(spacing: ThawSpacing.compact) {
                // A submenu does nothing itself, so there is nothing for keys to run.
                if !option.isSubmenu {
                    HotkeyRecorder(
                        keyCombination: keys(for: option, among: options),
                        onRecordingChange: { settings.isRecordingHotkey = $0 },
                        label: { Text(String(localized: "Keys", bundle: .floe, comment: "Spoken for the control that records the keys that run an action.")) }
                    )
                    .labelsHidden()
                    .fixedSize()
                }
                Toggle(isOn: shown(option)) {
                    Text("Show in the Actions menu")
                }
                .labelsHidden()
                .help(Text("Show in the Actions menu"))
            }
        } label: {
            Text(option.title)
                .lineLimit(1)
        }
    }

    private func returnChoice(among options: [ActionOption]) -> Binding<ActionID?> {
        Binding {
            settings.actionChoices[kind: kind].returnChoice(among: options)
        } set: { id in
            settings.actionChoices[kind: kind].setReturnChoice(id)
        }
    }

    private func shown(_ option: ActionOption) -> Binding<Bool> {
        Binding {
            settings.actionChoices[kind: kind].shows(option.id)
        } set: { isShown in
            settings.actionChoices[kind: kind].setShown(isShown, for: option.id)
        }
    }

    /// The keys in force on the row, Floe's until they are changed. Refused keys are not kept, so the recorder goes
    /// back to the row's keys, and the refusal says why under it.
    private func keys(for option: ActionOption, among options: [ActionOption]) -> Binding<KeyCombination?> {
        Binding {
            settings.actionChoices[kind: kind].keys(for: option.id, of: kind, hotkeys: settings.floeHotkeys)
        } set: { keys in
            var choices = settings.actionChoices[kind: kind]
            if let refused = choices.setKeys(keys, for: option.id, of: kind, among: options, hotkeys: settings.floeHotkeys) {
                refusal = (option.id, refused.message)
            } else {
                refusal = nil
                settings.actionChoices[kind: kind] = choices
            }
        }
    }
}
