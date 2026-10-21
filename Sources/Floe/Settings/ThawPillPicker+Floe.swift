//
//  ThawPillPicker+Floe.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

extension ThawPillPicker {
    /// One pill per value, in order, named by a title Floe has already localized, for a row whose label
    /// the caller lays out.
    init(selection: Binding<Value>, values: some Sequence<Value>, title: (Value) -> String) {
        self.init(selection: selection, options: values.map { Option($0, title: .verbatim(title($0))) })
    }
}
