//
//  ResolvedApps.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Combine
import Foundation

/// The apps the roles resolve to and where the Clipboard History command goes. Both reach LaunchServices,
/// which no keystroke should, so they are resolved once and kept until a choice, an app folder or the lookup changes.
final class ResolvedApps {
    /// How the terminal and the editor are looked up. Tests replace it, so they do not read this Mac's apps.
    var lookup = AppLookup.system {
        didSet { invalidate() }
    }

    private let settings: AppSettings
    private var cachedApps: [RoleApp]?
    private var cachedClipboardDestination: ClipboardDestination?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings) {
        self.settings = settings
    }

    var apps: [RoleApp] {
        if let cachedApps {
            return cachedApps
        }
        let resolved = PreferredApps.apps(choice: settings.appChoice, installed: lookup)
        cachedApps = resolved
        return resolved
    }

    var clipboardDestination: ClipboardDestination {
        if let cachedClipboardDestination {
            return cachedClipboardDestination
        }
        let resolved = settings.clipboardDestination(installed: lookup)
        cachedClipboardDestination = resolved
        return resolved
    }

    func invalidate() {
        cachedApps = nil
        cachedClipboardDestination = nil
    }

    /// A change to one of the choices resolves them again. Only the search needs this; the resident reads them seldom.
    func followChoices() {
        guard cancellables.isEmpty else { return }
        for change in [
            settings.$terminalApp.mapVoid(), settings.$editorApp.mapVoid(), settings.$browserApp.mapVoid(),
            settings.$clipboardHandler.mapVoid(), settings.$clipboardApp.mapVoid(), settings.$clipboardURL.mapVoid(),
        ] {
            change.sink { [weak self] _ in self?.invalidate() }
                .store(in: &cancellables)
        }
    }
}

private extension Published.Publisher {
    /// The changes only, not the value: what a cache drop listens for.
    func mapVoid() -> AnyPublisher<Void, Never> {
        map { _ in () }.eraseToAnyPublisher()
    }
}
