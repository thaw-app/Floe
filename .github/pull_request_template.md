# Summary

A brief description of the changes proposed in this pull request.

**Scope:** This PR changes one focused thing (bug fix or feature) plus minimal plumbing. Larger refactors need prior agreement in an issue.

> **External contributors:** before opening a PR for a bug fix or new feature, check the [issue tracker](https://github.com/thaw-app/Floe/issues) and the [TODO list](https://github.com/thaw-app/Floe#todo). Opening an issue first avoids work on something that is already in progress or out of scope.

## Linked issue

Replace `N/A` with `#<issue_number>` (e.g. `Closes: #123`) when this PR fixes or implements a specific issue.

Closes: N/A

## PR Type

Describe **what this change does** (not the linked issue's request kind). Bug *reports* use the `Bug` Issue type; bug *fixes* use `fix` on PRs.

If you tick **Feature** or **Refactor** and touch more than ~20 files, please mention why this can't be split.

- [ ] Bug fix
- [ ] CI/CD
- [ ] Documentation
- [ ] Feature
- [ ] Enhancement
- [ ] Performance improvement
- [ ] Refactor
- [ ] Test addition or update
- [ ] Other (please describe)

## Area

Optional. Path-based labeling also applies.

- Use **PR Type** for *what* changed (`CI/CD`, `Documentation`, `Other` / chore, etc.).
- Use **`ops`** for *where* when it is repo operations: CI, GitHub hygiene, scripts, docs, Sonar config.

- [ ] app
- [ ] runtime
- [ ] extensions
- [ ] vendor
- [ ] ops

## Does this PR introduce a breaking change?

- [ ] Yes - if yes, please describe the impact and migration path
- [ ] No

## What is the new behavior?

What does this PR change or add, and why?

## PR Checklist

- [ ] The PR title follows Conventional Commits (e.g. `fix(runtime): …`); PR Metadata checks this.
- [ ] I've built and run the app locally and verified that it works as expected.
- [ ] I've run the relevant checks from [docs/DEVELOPMENT.md](../docs/DEVELOPMENT.md) (list them below), e.g. `bun runtime/smoke.ts extensions/hello planets`.
- [ ] If I changed `project.yml`, I ran `xcodegen generate` and committed `Floe.xcodeproj`.
- [ ] I've noted which macOS versions I tested on.
- [ ] I've updated documentation as needed.
- [ ] If this PR changes dependencies / lockfiles (`Package.resolved`, `runtime/bun.lock`, Actions pins, etc.), `dependency-sca` is green, or any `.github/osv-scanner.toml` suppression includes both `reason` and `ignoreUntil` (see [security notes](../docs/SECURITY_NOTES.md#dependency-sca-policy)).

Checks run:

-

## Known limitations / follow-ups

- (optional) What is intentionally out of scope
- (optional) Follow-up issues or planned work

## Other information

Screenshots, notes, or anything useful for reviewers.
