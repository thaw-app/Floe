# Contributing to Floe

The [organization contribution policy](https://github.com/thaw-app/.github/blob/main/.github/CONTRIBUTING.md) covers review expectations, DCO sign-off, and AI-assisted work. These notes cover Floe-specific requirements. Floe's current PR Metadata workflow does not enforce DCO trailers; the shared policy still asks contributors to sign off commits.

## Issues and pull requests

- Target `main`.
- Check the README's [TODO list](https://github.com/thaw-app/Floe#todo) before starting work. Open an issue to coordinate a task.
- Use the [pull request template](../.github/pull_request_template.md). Use Conventional Commit titles; PR Metadata validates them.
- Expect deeper review for extension loading and execution, preferences, Keychain storage, and permissions.

For bug reports, include the version and commit from the About page. Name any involved extension and command, and say whether it came from Raycast's folder or Floe's. If Floe showed its error screen, use Copy Details (Cmd+Shift+C) and attach the result.

## Building

Requirements: macOS 26 or later, Xcode 27 for `Vendor/ThawUI`'s Swift 6.4 manifest, and [Bun](https://bun.sh). Install XcodeGen if changing `project.yml`.

```sh
cd runtime && bun install && cd ..
open Floe.xcodeproj
# Build, install, and launch /Applications/Floe.app:
./scripts/devrun.sh
```

Read [Development](DEVELOPMENT.md) for repository layout, build notes, and checks. Edit `project.yml` and run `xcodegen generate`, then commit both the spec and generated project. Changes to `Vendor/ThawUI` belong in Thaw first; the vendored revision is in `Vendor/ThawUI/UPSTREAM`.

## Checks

Run the checks relevant to your change, including the Swift/Bun round trip for runtime work:

```sh
bun runtime/smoke.ts extensions/hello planets
swift build && .build/debug/Floe --selftest hello planets
./scripts/coverage.sh --summary
```

The selftest must print `SELFTEST OK`. CI also runs Swift Testing and Bun tests through the coverage script. List the commands you ran in the PR.

Dependency SCA runs on pull requests and `main` pushes. Fix findings or document a suppression in `.github/osv-scanner.toml`; each suppression needs `reason` and `ignoreUntil`. See [security notes](SECURITY_NOTES.md#dependency-sca-policy) for thresholds. Dependabot changes must pass the same checks. Address new SonarQube Cloud findings and CodeQL high/critical findings, or discuss false positives with maintainers.

## Build a shareable DMG

Maintainers can run [Build DMG](../.github/workflows/build-dmg.yml) to create a signed, notarized DMG without creating a release. The artifact is retained for three days. On an internal PR, a maintainer can comment `.build` to start it for that branch.

```sh
gh workflow run build-dmg.yml -R thaw-app/Floe --ref YOUR_BRANCH
```

The signing job requires approval on `prod`. Only approve reviewed refs; their build scripts execute with signing credentials.

## Project documentation

- [Development](DEVELOPMENT.md).
- [Governance](../.github/GOVERNANCE.md).
- [Security notes](SECURITY_NOTES.md).
- [Code of Conduct](https://github.com/thaw-app/.github/blob/main/.github/CODE_OF_CONDUCT.md).
