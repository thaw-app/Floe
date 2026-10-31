# Floe project governance

How the Floe project makes decisions and who holds which roles.

## Decision model

Floe is an early project with one lead maintainer, hosted in the [`thaw-app`](https://github.com/thaw-app) GitHub organization next to [Thaw](https://github.com/thaw-app/Thaw). [Thaw's governance](https://github.com/thaw-app/Thaw/blob/development/.github/GOVERNANCE.md) also applies to Floe, with its leads, release secret rules and continuity plan. Where this document says something more specific about Floe, this document decides.

1. **Day-to-day:** The maintainer reviews and merges pull requests to `development` and triages issues. Informal discussion often happens in the Thaw community's [Discord](https://discord.gg/KDfWjWDnR4), where Floe is discussed too; GitHub issues and pull requests remain the record for decisions that affect the codebase.
2. **Direction:** The maintainer decides on roadmap, licensing, security policy and breaking product behavior. The [roadmap](https://www.getthaw.app/floe/roadmap) is on the website.
3. **Consensus preferred:** The maintainer and contributors seek rough consensus in issues and pull requests before a decision is made.
4. **Organization:** The repository belongs to the `thaw-app` organization, so the organization's owners can administer it if the maintainer is unavailable.
5. **Security:** Vulnerability handling follows the [organization Security Policy](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md). Public discussion of unfixed vulnerabilities is not appropriate.

Forking remains always available under the AGPL-3.0 license; governance here only describes how *this* project operates.

## Roles and responsibilities

| Role | Who (GitHub) | Responsibilities |
| --- | --- | --- |
| **Maintainer** | [@diazdesandi](https://github.com/diazdesandi) | Product and roadmap decisions; review and merge of pull requests; issue triage; CI; Code of Conduct enforcement |
| **Organization owner** | [@stonerl](https://github.com/stonerl), [@nightah](https://github.com/nightah), [@diazdesandi](https://github.com/diazdesandi) | Admin of [`thaw-app`](https://github.com/thaw-app): org settings, membership, org-owned repositories |
| **Write collaborator** | Everyone else with write access to [thaw-app/Floe](https://github.com/thaw-app/Floe) | Code and docs only: no secret read, and can't approve the `prod` Environment |
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
| [thaw-app/org-ci](https://github.com/thaw-app/org-ci) | Shared GitHub Actions and the reusable workflow that builds and attests releases |
| [thaw-app/.github](https://github.com/thaw-app/.github) | The contribution guidelines, Code of Conduct and Security Policy Floe follows |

The same organization owners administer all of these, and Floe pins `org-ci` by commit.

Public contributor history: https://github.com/thaw-app/Floe/graphs/contributors

## Releases and secrets

Two manual workflows build signed, notarized DMGs: [Build DMG](workflows/build-dmg.yml) uploads one as a short-lived artifact, and [Release](workflows/release.yml) publishes one as a GitHub Release for an existing tag.

Both read the Apple Developer ID certificate and notarization credentials from GitHub Actions secrets; none of that material is committed to git. The secrets exist only in the `prod` Environment. The job that signs, in either workflow, runs in that Environment and waits for the maintainer's approval before the secrets are used; organization owners can bypass that wait. Write access alone gives no way to read the secrets or approve that wait. The maintainer starts releases.

## Code review

Every change reaches `development` through a pull request. Branch protection requires the `lint`, `build`, `sonarqube` and `dependency-sca` checks, signed commits, resolved conversations, and an approval from a person with write access other than the last pusher. CodeRabbit and SonarCloud inform a review but don't replace one.

The maintainer is the code owner of every file, so a contributor's change needs the maintainer's approval. Organization owners can bypass branch protection, and the maintainer's own pull requests need that bypass because nobody else can give the code owner's approval. The maintainer asks another person with write access to review those pull requests too.

A reviewer checks that:

- the change does what the pull request says, stays on one subject, and doesn't hide a failing check;
- new behavior has tests and a bug fix has a regression test, following the [coding standards](../docs/CODING_STANDARDS.md);
- the documentation and the changelog match the change;
- every commit is signed off;
- the author can explain the change, including any AI-assisted part.

These changes also get a security read against the [assurance case](../docs/ASSURANCE_CASE.md), which is updated when a trust boundary moves: link handling, sign-in and tokens, the Keychain, messages between processes, how extensions run or install, and the release and update workflows.

Reviews are recorded as approvals on the pull request.

## Continuity

Floe has one lead maintainer today. Because the repository is owned by the `thaw-app` organization, the other organization owners keep admin access to it: they can accept changes, close issues, grant write access to a new maintainer and start a release, since the signing secrets stay in the `prod` Environment. [Thaw's continuity plan](https://github.com/thaw-app/Thaw/blob/development/.github/GOVERNANCE.md#continuity) covers the rest.

## Related documents

- [Thaw's governance](https://github.com/thaw-app/Thaw/blob/development/.github/GOVERNANCE.md)
- [Contributing](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md)
- [Code of Conduct](https://github.com/thaw-app/.github/blob/main/.github/CODE_OF_CONDUCT.md)
- [Security Policy](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md)
- [docs/DEVELOPMENT.md](../docs/DEVELOPMENT.md)
