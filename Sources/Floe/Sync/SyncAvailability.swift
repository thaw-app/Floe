//
//  SyncAvailability.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Security

/// Which of iCloud's stores this build is signed for.
nonisolated enum SyncBackend: Equatable, Sendable {
    case cloudKit(container: String)
    case keyValueStore
    case none
}

/// Whether sync can work in this process at all. Both answers are closures so a test decides them.
struct SyncAvailability {
    /// Whether this build is signed with an entitlement for one of iCloud's stores.
    var isEntitled: () -> Bool
    /// Whether an iCloud account is signed in on this Mac.
    var hasAccount: () -> Bool

    static let keyValueEntitlement = "com.apple.developer.ubiquity-kvstore-identifier"
    static let containerEntitlement = "com.apple.developer.icloud-container-identifiers"
    static let servicesEntitlement = "com.apple.developer.icloud-services"

    /// Asked of the running process, so no store is ever touched by a build that may not use it.
    static func systemBackend() -> SyncBackend {
        guard let task = SecTaskCreateFromSelf(nil) else { return .none }
        let value = { (name: String) -> Any? in SecTaskCopyValueForEntitlement(task, name as CFString, nil) }
        return backend(containers: value(containerEntitlement), services: value(servicesEntitlement), keyValueStore: value(keyValueEntitlement))
    }

    /// CloudKit when the build has a container and the service, else the key-value store when it has that.
    static nonisolated func backend(containers: Any?, services: Any?, keyValueStore: Any?) -> SyncBackend {
        let container = (containers as? [String])?.first { !$0.isEmpty }
        if let container, (services as? [String])?.contains("CloudKit") == true {
            return .cloudKit(container: container)
        }
        return (keyValueStore as? String)?.isEmpty == false ? .keyValueStore : .none
    }
}

/// Whether iCloud has an account, as CloudKit last said. It starts as a guess and the store corrects it.
final class CloudSyncAccount {
    var isSignedIn: Bool

    init(isSignedIn: Bool) {
        self.isSignedIn = isSignedIn
    }
}

/// The store a build uses, with the two checks that go with it.
struct SyncSetup {
    var availability: SyncAvailability
    var makeStore: () -> any SyncStore

    /// `folder` is where a store that keeps files puts them.
    static func system(folder: URL, backend: SyncBackend = SyncAvailability.systemBackend()) -> SyncSetup {
        let hasIdentity = { FileManager.default.ubiquityIdentityToken != nil }
        switch backend {
        case let .cloudKit(container):
            let account = CloudSyncAccount(isSignedIn: hasIdentity())
            return SyncSetup(
                availability: SyncAvailability(isEntitled: { true }, hasAccount: { account.isSignedIn }),
                makeStore: { CloudKitSyncStore(container: container, files: .folder(folder), account: account) }
            )
        case .keyValueStore:
            return SyncSetup(availability: SyncAvailability(isEntitled: { true }, hasAccount: hasIdentity), makeStore: { UbiquitousSyncStore() })
        case .none:
            // The engine makes no store without the entitlement; this one would touch nothing if it did.
            return SyncSetup(availability: SyncAvailability(isEntitled: { false }, hasAccount: { false }), makeStore: { MemorySyncStore() })
        }
    }
}
