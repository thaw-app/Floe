# Licenses

Floe is licensed under the [GNU Affero General Public License, version 3](../LICENSE).
Parts of it come from other projects and keep their own terms. This folder holds those terms.

| What | Where in the tree | License | Text |
| --- | --- | --- | --- |
| Floe's own code | `Sources/Floe`, `runtime`, `scripts` | AGPL-3.0 | [`LICENSE`](../LICENSE) |
| Code ported from Thaw | `Sources/Floe/Thaw`, `Vendor/ThawUI`, `Fuzzing/Sources/FuzzIncomingLink/FuzzIncomingLink.swift` | GPL-3.0 | [`Thaw-GPL-3.0`](Thaw-GPL-3.0) |
| Code ported from Droppy Code | `Sources/Floe/DroppyCode` | AGPL-3.0 with attribution terms | [`DroppyCode-LICENSE`](DroppyCode-LICENSE), [`DroppyCode-THIRD_PARTY_NOTICES.md`](DroppyCode-THIRD_PARTY_NOTICES.md) |
| Code adapted from Barometer | `Sources/Floe/Barometer` | GPL-3.0 | [`Thaw-GPL-3.0`](Thaw-GPL-3.0), the same license |
| Code adapted from Audio Priority Bar | `Sources/Floe/AudioPriorityBar` | MIT | [`AudioPriorityBar-MIT`](AudioPriorityBar-MIT) |
| Code adapted from CMD-Z | `Sources/Floe/CMDZ` | MIT | [`CMD-Z-MIT`](CMD-Z-MIT) |
| Sample extensions | `extensions` | Each extension's own | In each extension's folder |
| Test cases copied from fend | `Tests/FloeTests/Fixtures/FendIntegrationCorpus.swift` | MIT | [`fend-MIT`](fend-MIT) |

Section 13 of the GPL-3.0 allows combining GPL-3.0 code with AGPL-3.0 code in one program, which is how
Thaw's and Barometer's files and Floe's sit together. Each ported file says in its header where it came from and what Floe
changed.

The packages Floe links against, with their versions and licenses, are listed in [`CREDITS.md`](../CREDITS.md).
