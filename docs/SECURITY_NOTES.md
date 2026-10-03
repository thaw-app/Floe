# Floe security notes

The [organization Security Policy](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md) defines private reporting and coordinated disclosure. These notes describe Floe's support window, extension trust model, and dependency checks.

## Supported Versions

Floe is a launcher for macOS that runs Raycast extensions. There are no releases yet: the app is built from source, and only the current `main` branch is supported. Please reproduce on an up-to-date `main` before submitting a vulnerability report.

| Version | Supported          |
| ------- | ------------------ |
| `main`  | :white_check_mark: |
| Older commits | :x:          |

## Security requirements (what users can and cannot expect)

### You can expect

- Local-first: Floe does not require an account and does not operate a first-party tracking or analytics backend.
- Explicit permissions: features that need Accessibility, such as opening a menu bar item's menu, ask via normal macOS TCC prompts and do not work without those grants.
- Password preferences of extensions are stored in the Keychain.
- Coordinated disclosure: a private reporting channel in the organization Security Policy.

### You cannot expect

- Sandboxing of extensions. An extension is third-party code that Floe runs with Bun under your user account. It can read your files and use the network like any other program you run. Only add extensions you trust.
- Protection against attackers who already control your unlocked Mac session, or who hold the same TCC permissions.
- Signed or notarized builds. Builds from source are ad hoc signed.
- That third-party extensions, or the apps Floe interacts with, are themselves secure.

## Scope of Security Reports

**In scope**

- Privilege escalation (e.g. escaping intended privilege boundaries).
- Unauthorized access to local user data managed by the app, such as extension preferences or Keychain items.
- Execution of arbitrary code via malicious input that the user did not choose to run, for example crafted data that an extension passes to Floe, or crafted configuration.

**Generally out of scope**

- An extension doing harm with the access every extension has. Report that to the extension's author.
- Crashes without a viable exploit path.
- Issues requiring physical access to an unlocked Mac.
- Issues solely in third-party macOS components, Bun, or other apps, unless Floe needs a specific mitigation.
- Social engineering of maintainers outside the product.

## Response expectations

Floe has one maintainer; acknowledgement is best effort without a fixed response deadline. Include the version and commit from the About page in private reports. Disclosure follows the organization policy after the fix reaches `main`, or at a coordinated time. Timelines depend on complexity and whether an OS update is required.

## Dependency SCA policy

Floe evaluates every proposed change for known-vulnerable dependencies. This is the project's software composition analysis (SCA) gate (OpenSSF Baseline **OSPS-VM-05.03**).

### What is evaluated

On every pull request and on pushes to `main`, the **Dependency SCA** workflow (`.github/workflows/dependency-sca.yml`) runs a version-and-SHA256-pinned [OSV-Scanner](https://google.github.io/osv-scanner/) binary against the checked-in lockfiles: the Swift `Package.resolved` files and `runtime/bun.lock`. Findings are also uploaded to GitHub code scanning when permissions allow.

Dependabot opens update PRs; those PRs are subject to the same gate.

### Pass / fail thresholds

| Finding | Gate behavior |
| --- | --- |
| Any **unsuppressed** vulnerability reported by OSV-Scanner for scanned artifacts | **Fail**: the `dependency-sca` check is red |
| Vulnerability listed in `.github/osv-scanner.toml` with a documented **reason** and **ignoreUntil** expiry | **Pass** (suppressed): treated as an accepted residual risk |

There is no severity carve-out for High/Critical only: if OSV reports it and it is not suppressed, the check fails.

### Suppressions (non-exploitable / accepted risk)

Suppressions are **checked in** under `.github/osv-scanner.toml` so they are reviewable in the same PR as the waiver:

```toml
[[IgnoredVulns]]
id = "GHSA-xxxx-xxxx-xxxx"
ignoreUntil = 2026-12-31
reason = "Not exploitable in Floe: …"
```

Rules for maintainers:

1. Prefer upgrading or removing the dependency over suppressing.
2. Every suppression needs a **reason** tied to Floe's threat model (e.g. not reachable, unused feature, fix not yet published).
3. Every suppression needs **`ignoreUntil`** (YYYY-MM-DD) so waivers expire and get revisited. The `dependency-sca` workflow rejects entries missing `reason` or `ignoreUntil`.

### Related docs

- Contributor expectations: [Contributor notes](CONTRIBUTOR_NOTES.md#checks)

## Public vulnerability history

Published advisories (when any exist):
https://github.com/thaw-app/Floe/security/advisories

If there are no published advisories, that means none have been disclosed yet, not that the project ignores reports.
