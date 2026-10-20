//
//  ListStepping.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

extension Array {
    /// The item `offset` away from the current one, for the arrow keys: the first item when none is current yet,
    /// and nil past either end, where the selection stays.
    func item(stepping offset: Int, from isCurrent: (Element) -> Bool) -> Element? {
        guard let current = firstIndex(where: isCurrent) else { return first }
        return indices.contains(current + offset) ? self[current + offset] : nil
    }
}
