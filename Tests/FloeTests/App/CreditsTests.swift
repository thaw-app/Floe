//
//  CreditsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Credits.swift is written by scripts/generate-credits.py; these catch a script change that breaks the list.
struct CreditsTests {
    @Test func theListNamesWhatFloeIsBuiltFrom() {
        let names = Credits.all.map(\.name)
        for expected in ["Thaw", "Droppy Code", "CompactSlider", "fend", "Bun", "React", "react-reconciler", "Raycast extensions"] {
            #expect(names.contains(expected), "\(expected)")
        }
    }

    @Test func namesAreUniqueBecauseThePageUsesThemAsIdentifiers() {
        #expect(Set(Credits.all.map(\.id)).count == Credits.all.count)
    }

    @Test func everyEntryHasALinkNameAndADetailSentence() {
        for credit in Credits.all {
            #expect(!credit.link.isEmpty, "\(credit.name)")
            #expect(credit.detail.hasSuffix("."), "\(credit.name)")
        }
    }

    @Test func droppyCodeIsCreditedInTheWordsItsLicenseAsksFor() {
        let credit = Credits.all.first { $0.name == "Droppy Code" }
        #expect(credit?.detail.contains("Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app") == true)
    }

    @Test func onlyDroppyCodeIsUsedByPermission() {
        let withPermission = Credits.all.filter { $0.detail.localizedCaseInsensitiveContains("permission") }
        #expect(withPermission.map(\.name) == ["Droppy Code"])
    }

    @Test func thawIsCreditedWithThePagesFloeTakesFromIt() {
        let credit = Credits.all.first { $0.name == "Thaw" }
        #expect(credit?.detail.contains("the About and acknowledgements pages") == true)
        #expect(credit?.detail.hasSuffix("Copyright © 2026 Toni Förster et al. GPL-3.0.") == true)
    }

    @Test func originsAreTheProjectsFloeCarriesCodeFromAndTheRestAreLibraries() {
        #expect(Credits.origins.map(\.name) == ["Thaw", "Droppy Code"])
        #expect(Credits.origins.count + Credits.libraries.count == Credits.all.count)
        #expect(Credits.libraries.allSatisfy { $0.group == .library })
    }

    @Test func theCreditsPageLinksToTheRepositoryAndNamesNobody() {
        let repository = URL(string: "https://github.com/thaw-app/Floe")
        #expect(AcknowledgementLinks.contributors(repository: repository)?.absoluteString == "https://github.com/thaw-app/Floe/graphs/contributors")
        #expect(AcknowledgementLinks.translators(repository: repository)?.absoluteString == "https://github.com/thaw-app/Floe/blob/main/CREDITS.md")
        #expect(AcknowledgementLinks.contributors(repository: nil) == nil, "a build with no repository link shows no link")
    }

    @Test func aLinkIsPrintedAsItsHostAndPath() throws {
        let url = try #require(URL(string: "https://github.com/thaw-app/Thaw"))
        #expect(AcknowledgementsView.displayText(for: url) == "github.com/thaw-app/Thaw")
    }

    @Test func theTrademarkNoteNamesRaycast() {
        #expect(Credits.trademark.contains("Raycast"))
    }
}
