# Floe project governance

How the Floe project makes decisions and who holds which roles.

## Decision model

Floe is an early project with one maintainer, hosted in the [`thaw-app`](https://github.com/thaw-app) GitHub organization next to [Thaw](https://github.com/thaw-app/Thaw).

1. **Day-to-day:** The maintainer reviews and merges pull requests to `main` and triages issues. Informal discussion often happens in the Thaw community's [Discord](https://discord.gg/KDfWjWDnR4), where Floe is discussed too; GitHub issues and pull requests remain the record for decisions that affect the codebase.
2. **Direction:** The maintainer decides on roadmap, licensing, security policy and breaking product behavior. The [TODO list](https://github.com/thaw-app/Floe#todo) in the README is the current roadmap.
3. **Consensus preferred:** The maintainer and contributors seek rough consensus in issues and pull requests before a decision is made.
4. **Organization:** The repository belongs to the `thaw-app` organization, so the organization's owners can administer it if the maintainer is unavailable.
5. **Security:** Vulnerability handling follows the [organization Security Policy](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md). Public discussion of unfixed vulnerabilities is not appropriate.

Forking remains always available under the GPL-3.0 license; governance here only describes how *this* project operates.

## Roles and responsibilities

| Role | Who (GitHub) | Responsibilities |
| --- | --- | --- |
| **Maintainer** | [@diazdesandi](https://github.com/diazdesandi) | Product and roadmap decisions; review and merge of pull requests; issue triage; CI; Code of Conduct enforcement |
| **Organization owner** | [@stonerl](https://github.com/stonerl), [@nightah](https://github.com/nightah), [@diazdesandi](https://github.com/diazdesandi) | Admin of [`thaw-app`](https://github.com/thaw-app): org settings, membership, org-owned repositories |
| **Contributor** | Anyone submitting issues, pull requests or docs | Follow [Thaw/Floe contribution policy](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md) and the [organization Code of Conduct](https://github.com/thaw-app/.github/blob/main/.github/CODE_OF_CONDUCT.md) |
| **Security contact** | Maintainer (via [private vulnerability reporting](https://github.com/thaw-app/Floe/security/advisories/new)) | Acknowledge and coordinate vulnerability reports |

## Community channels

| Channel | Purpose |
| --- | --- |
| [GitHub Issues / PRs](https://github.com/thaw-app/Floe) | Bugs, features, code review, durable decisions |
| [Discord](https://discord.gg/KDfWjWDnR4) | The Thaw community's server, where Floe is discussed too |

## Repository

| Location | Status |
| --- | --- |
| [thaw-app/Floe](https://github.com/thaw-app/Floe) | Canonical source, issues, CI |
| [thaw-app/Thaw](https://github.com/thaw-app/Thaw) | Upstream of `Vendor/ThawUI` and of the hotkey code in `Sources/Floe/Thaw` |

Public contributor history: https://github.com/thaw-app/Floe/graphs/contributors

## Releases and secrets

Floe has no releases yet. Two manual workflows build signed, notarized DMGs: [Build DMG](workflows/build-dmg.yml) uploads one as a short-lived artifact, and [Release](workflows/release.yml) publishes one as a GitHub Release for an existing tag.

Both read the Apple Developer ID certificate and notarization credentials from GitHub Actions secrets; none of that material is committed to git. The secrets exist only in the `prod` Environment. The job that signs, in either workflow, runs in that Environment and waits for the maintainer's approval before the secrets are used. The maintainer starts releases.

## Continuity

Floe has one maintainer today. Because the repository is owned by the `thaw-app` organization, the other organization owners keep admin access to it and can grant write access to a new maintainer if the current one becomes unavailable.

## Related documents

- [Contributing](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md)
- [Code of Conduct](https://github.com/thaw-app/.github/blob/main/.github/CODE_OF_CONDUCT.md)
- [Security Policy](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md)
- [docs/DEVELOPMENT.md](../docs/DEVELOPMENT.md)
