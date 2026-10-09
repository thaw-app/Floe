@testable import Floe
import Foundation
import Testing

@MainActor
@Suite("Hotkeys for built-in commands")
struct BuiltInHotkeysTests {
    private func makeModel() -> (LauncherModel, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-hotkeys-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "floe-hotkeys-tests-\(UUID().uuidString)")!)
        let model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: []))
        model.receipts = ReceiptStore(file: folder.appendingPathComponent("Receipts.json"))
        model.checkpointStore = CheckpointStore(file: folder.appendingPathComponent("Checkpoints.json"))
        return (model, folder)
    }

    @Test func everyBuiltInCommandThatTakesAHotkeyHasAKeyOfItsOwn() {
        let keys = LauncherModel.hotkeyItems.compactMap(\.settingsKey)
        #expect(keys.count == LauncherModel.hotkeyItems.count, "each can be stored")
        #expect(Set(keys).count == keys.count, "no two share a key")
        #expect(keys.prefix(4) == [RootItem.menuBarSearchKey, RootItem.emojiSearchKey, RootItem.clipboardHistoryKey, RootItem.fileSearchKey])
        #expect(keys.count == 4 + SystemCommand.allCases.count)
    }

    @Test func onlyTheCommandsGivenAHotkeyAreRegistered() {
        let emoji = KeyCombination(key: .e, modifiers: [.command, .option])
        let lock = KeyCombination(key: .l, modifiers: [.command, .option])
        let assigned = LauncherModel.assigned([
            RootItem.emojiSearchKey: emoji,
            "system:\(SystemCommand.lockScreen.rawValue)": lock,
            "some.extension.command": KeyCombination(key: .x, modifiers: [.command, .option]),
        ])
        #expect(assigned.map(\.item.id) == [RootItem.emojiSearch.id, RootItem.system(.lockScreen).id])
        #expect(assigned.map(\.keys) == [emoji, lock])
        #expect(LauncherModel.assigned([:]).isEmpty)
    }

    @Test func aViewsHotkeyOpensThePanelOnThatView() {
        let (model, folder) = makeModel()
        defer { try? FileManager.default.removeItem(at: folder) }
        var shown = 0
        model.showPanel = { shown += 1 }

        model.query = "half typed"
        model.runFromHotkey(.emojiSearch)
        #expect(model.query == EmojiSearchProvider.prefix)
        #expect(shown == 1)

        model.runFromHotkey(.fileSearch)
        #expect(model.isSearchingFiles)
        #expect(model.query.isEmpty, "the emoji search it replaced is gone")
        #expect(shown == 2)

        model.runFromHotkey(.menuBarSearch)
        #expect(model.isSearchingMenuBar)
        #expect(shown == 3)
    }
}
