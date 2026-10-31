# Floe security assurance case

This document argues that Floe meets its [security requirements](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md)
for its intended environment: a local macOS launcher used by one person on their own Mac. It follows the structure of
Thaw's assurance case, but Floe's risks are its own. The largest is that Floe runs third-party extensions without a sandbox.

Update it when a trust boundary or a major feature changes.

## Security requirements

You can expect that:

1. Floe runs on your Mac, with no Floe account and no analytics. Its data stays on the Mac unless you turn on iCloud sync
   or use a feature that talks to a service you chose, such as an AI provider or a sign-in.
2. macOS asks before Floe gets a protected permission, such as Accessibility, Calendar or Contacts.
3. A link from another app can't complete a sign-in or change Floe's look unless it answers a request Floe made.
4. Passwords, sign-in tokens and AI keys are kept in the Keychain. Sign-in tokens belong to the installed extension that
   saved them, and an AI key belongs to the address it was saved for.
5. Updates come over HTTPS and are checked with Sparkle's EdDSA signature. Releases are signed with a Developer ID and
   notarized. See [Verifying releases](VERIFYING_RELEASES.md).
6. You can report a security problem privately, and the maintainers aim to acknowledge it within 48 hours.

You can't expect that:

1. An extension or script command is contained. It runs under your account and can reach your files and the network.
   Only run code you trust.
2. Floe protects you from someone who already controls your unlocked Mac session.
3. Older releases get security fixes. Only the latest stable release is supported.

## Threat model

### What needs protecting

| Asset | Why it matters |
| --- | --- |
| Update channel | A forged update would run code as you |
| Sign-in tokens, passwords and AI keys | They give access to your accounts on other services |
| Your files, clipboard history and snippets | They can hold private text |
| Permissions macOS granted to Floe | Accessibility, Apple Events, Calendar and Contacts are powerful |
| Floe's settings | Changing them could change what Floe does or runs |

### Scenarios

| ID | Scenario | Likelihood | Impact |
| --- | --- | --- | --- |
| T1 | A malicious or compromised extension | Medium | Code running as you, with access to your files |
| T2 | Another app opens a crafted `floe://` or Raycast link | Medium | A forged sign-in or appearance answer |
| T3 | Another app posts Floe's distributed notifications | Medium | Forged messages between Floe's two processes |
| T4 | Compromise of a dependency or CI | Low to medium | Code running in Floe |
| T5 | A tampered download or update | Low | Code running as you |
| T6 | A malicious server answers an AI or update request | Low | Bad text shown, or an update refused |
| T7 | A crafted settings import or sync record | Low | Wrong settings or a crash |

Out of scope: physical access to an unlocked Mac, bugs in macOS, and compromise of Apple's notarization service.

## Trust boundaries

```text
  Other apps and scripts                     You
     │ floe:// links, notifications          │ the launcher, Settings, macOS prompts
     ▼                                       ▼
  ┌───────────────────── Floe (your account) ─────────────────────┐
  │  link routing and request checks  │  signed process messages  │
  └───┬───────────────────┬───────────────────┬───────────────┬───┘
      │ stdin/stdout      │ Sparkle           │ AppleScript   │ Keychain
      ▼                   ▼                   ▼               ▼
  Bun, one per command   HTTPS and EdDSA    Other apps      macOS
  (no sandbox)
```

| Boundary | What crosses | Controls |
| --- | --- | --- |
| Other apps to Floe | `floe://`, `raycast://` and `com.raycast:` links | `IncomingLink` accepts known schemes and hosts only, and is fuzzed. A sign-in's return must carry the state of a waiting sign-in, used once, within ten minutes. Thaw's answer must carry the random id of the request that is out, used once, within five seconds |
| Launcher to Settings process | Distributed notifications | Each message is signed with a key made for that settings process and handed over a pipe, and numbers must count up, so a copied or forged message is dropped |
| Floe to an extension | NDJSON over stdin and stdout | A record of what the extension reached, shown in Settings. This is a record and not a limit |
| Store to your Mac | Extension source from `raycast/extensions` over HTTPS | You choose what to install. Dependencies install with scripts off (`bun install --ignore-scripts`) |
| Floe to AI services | Prompts and keys | A key goes only to the address it was saved for, and only over HTTPS or to a server on this Mac |
| Floe to the network | Update feed and downloads | HTTPS, and Sparkle's EdDSA key in `SUPublicEDKey`. App Transport Security allows plain HTTP only to local addresses, for local model servers. Floe's own code opens no listening socket |
| Floe to macOS | Permissions and Apple Events | macOS prompts, and features that wait until you grant the permission. Floe's own search of browser tabs and files stays off until you switch it on in Settings › Privacy |

## Secure design principles

These are the Saltzer and Schroeder principles.

| Principle | How Floe applies it |
| --- | --- |
| Economy of mechanism | One link router, and one small file that decides what a link is |
| Fail-safe defaults | An unknown link does nothing. Sync, search sources and iCloud passwords are off until you choose them. Extensions install with scripts off |
| Complete mediation | Every link and every process message is checked when it arrives |
| Open design | The code is AGPL-3.0, and the security policy and this document are public |
| Separation of privilege | Release signing runs only in the `prod` environment, separate from pull request CI. Settings runs as its own process |
| Least privilege | Floe doesn't ask for root, and macOS grants each protected permission separately. Its entitlements are listed in `Resources/Floe.entitlements`. Extensions are the exception, as the first residual risk says |
| Least common mechanism | Each extension command gets its own Bun process. Floe is a per-user app with no shared service |
| Psychological acceptability | Settings shows what each extension has reached, and macOS prompts say why Floe asks |

## Common weaknesses countered

| Weakness | Countermeasure |
| --- | --- |
| Memory corruption (CWE-119) | Swift, Rust and TypeScript. `unsafe` is limited to system and language boundaries |
| Forged requests (CWE-346, CWE-352) | State and request ids checked against what Floe asked for. Signed process messages |
| Injection into AppleScript (CWE-94) | Values pass through `AppleScript.literal` |
| Credential exposure (CWE-522) | Keychain storage, keys bound to their address, no key over plain HTTP to another machine |
| Insecure update (CWE-494) | HTTPS, Sparkle EdDSA, Developer ID and notarization. SLSA provenance and Sigstore signatures on releases |
| Secrets in the repository (CWE-798) | Signing material lives in the `prod` environment's secrets |
| Vulnerable dependencies (CWE-1395) | Locked versions, Dependabot and OSV scanning that must pass before merge |

CodeQL, SonarCloud and SwiftLint run in CI. A nightly fuzz run with AddressSanitizer covers `IncomingLink`.

## Residual risks

1. **Extensions aren't contained.** This is Floe's largest risk, and it comes with running unmodified Raycast extensions.
   An extension can read your files, reach the network, start programs and run scripts in your browser's tabs through
   the BrowserExtension API. Floe records what it sees, which a hostile extension could avoid. Floe also doesn't disclaim
   responsibility for its child processes, so macOS may treat an extension's request as Floe's and apply the permissions
   you gave Floe.
2. **Store extensions aren't pinned.** They come from the current `raycast/extensions` tree, so Floe relies on GitHub's
   HTTPS and that repository's review. Floe doesn't check a signature on them.
3. **Bun runs with loosened code signing.** To run JavaScript, the bundled Bun has JIT and unsigned executable memory
   allowed, library validation off and `DYLD` variables allowed. Anyone who can already run code as you could use those
   entitlements, and Bun is signed with Floe's team.
4. **Sign-in goes through raycast.com for now.** Raycast's page sends the browser back to Floe. It's temporary and may stop
   working, as [What Floe does not do yet](LIMITATIONS.md) says.
5. **Local apps can see process notifications.** Signatures stop forgery, but another app can read a message and its
   payload, such as the settings page on screen. The one link sent this way is Thaw's appearance answer; a sign-in's
   return is never forwarded.
6. **Fuzzing covers one parser.** It covers link routing and the sign-in state. It doesn't cover Thaw's appearance answers,
   settings import or extension manifests, which rely on Swift's memory safety and unit tests.
7. **Coverage has limits.** Statement coverage is measured on SonarCloud against the exclusions in
   `sonar-project.properties`. Branch coverage isn't measured.

## Evidence

| Claim | Evidence |
| --- | --- |
| Reporting and response | [Security Policy](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md) |
| Attack surface | [External interfaces](INTERFACES.md) |
| Link routing | `Sources/Floe/App/IncomingLink.swift`, `Sources/Floe/App/IncomingURLRouter.swift`, `.github/workflows/fuzz.yml` |
| Sign-in and token rules | `Sources/Floe/Extensions/OAuthBroker.swift` |
| Process messages | `Sources/Floe/App/ProcessLink.swift` |
| AI key rules | `Sources/Floe/AI/AISources.swift`, `AIEndpoint` in `Sources/Floe/Extensions/HostRequest.swift` |
| Update and release authenticity | [Verifying releases](VERIFYING_RELEASES.md), `.github/workflows/release.yml` |
| Architecture | [Architecture](ARCHITECTURE.md) |
| Automated analysis | `.github/workflows/ci.yml`, `codeql.yml`, `dependency-sca.yml`, `fuzz.yml`, SonarCloud project `thaw-app_Floe` |
| Security scans | CodeRabbit's scans of 0.1.0 ([#45](https://github.com/thaw-app/Floe/pull/45)) and 0.2.0 ([#53](https://github.com/thaw-app/Floe/pull/53)), with fixes in the [changelog](../CHANGELOG.md) |

## Revision

| Date | Note |
| --- | --- |
| 2026-10-30 | First version, for the OpenSSF Best Practices `assurance_case` and `security_review` criteria |
