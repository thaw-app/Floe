# Verifying Floe releases

If you install Floe from a GitHub Release and update it in the app, macOS and Sparkle do these checks for you. This
page is for checking a download yourself.

## What is signed

| Layer | What it proves | Covers |
| --- | --- | --- |
| Apple Developer ID and notarization | The app came from Floe's Apple developer team (`A7CKWF99ML`) and passed Apple's checks | The app and the DMG |
| Sparkle EdDSA | An update matches what the release workflow signed with Floe's Sparkle key | Update ZIPs and deltas |
| Sigstore (cosign) | The file matches a signature made by Floe's release workflow | The DMG and the SBOM |
| SLSA build provenance | The shared `thaw-app/org-ci` build workflow built the file from the tagged commit (SLSA v1.0 Build L3) | The DMG and the SBOM |
| GPG tag signature | The maintainer tagged that commit | Git version tags, after 0.2.1 |

Each release also has a CycloneDX SBOM, `Floe_<version>.cdx.json`, which lists the Swift packages linked into the app.

The Apple credentials and the Sparkle private key are CI secrets, held in the repository's `prod` environment.

## Check the app

Open the DMG, then run:

    spctl --assess --type execute -v /Volumes/Floe/Floe.app
    xcrun stapler validate /Volumes/Floe/Floe.app
    codesign --verify --deep --strict --verbose=2 /Volumes/Floe/Floe.app
    codesign -dv --verbose=4 /Volumes/Floe/Floe.app 2>&1 | grep -E 'Authority|TeamIdentifier|Timestamp'

`spctl` should say `accepted` and `source=Notarized Developer ID`, and `TeamIdentifier` should be `A7CKWF99ML`.

## Check the checksum and the Sigstore signature

Download `Floe.dmg`, `Floe.dmg.sha256` and `Floe.dmg.sigstore.json` from the release into one folder. You need
[cosign](https://docs.sigstore.dev/cosign/system_config/installation/) for the second command.

    shasum -a 256 -c Floe.dmg.sha256

    cosign verify-blob \
      --bundle Floe.dmg.sigstore.json \
      --certificate-identity-regexp '^https://github\.com/thaw-app/Floe/\.github/workflows/release\.yml@refs/' \
      --certificate-oidc-issuer https://token.actions.githubusercontent.com \
      Floe.dmg

The SBOM works the same way, with `Floe_<version>.cdx.json` in place of `Floe.dmg`.

## Check the build provenance

This needs the [GitHub CLI](https://cli.github.com). For releases after 0.2.1:

    gh attestation verify Floe.dmg --repo thaw-app/Floe \
      --signer-workflow thaw-app/org-ci/.github/workflows/build-macos-app.yml

`--signer-workflow` ties the check to the workflow that built the file. This repository's release workflow can call
that workflow but can't change it.

Releases up to 0.2.1 were attested at Build L2 by a workflow in this repository. Check those with:

    gh attestation verify Floe.dmg --repo thaw-app/Floe \
      --signer-workflow thaw-app/Floe/.github/workflows/attest-build-provenance.yml

The same attestations are attached to each release as `*.intoto.jsonl`.

## Check a Git tag

Tags after 0.2.1 are signed with the maintainer's GPG key, whose fingerprint is
`DC99 B6ED B84A 220A E164 38D1 1EDC BC96 0CD9 1D90`. GitHub lists the same key at
<https://github.com/diazdesandi.gpg>. Compare the two before you trust the key.

    curl -s https://github.com/diazdesandi.gpg | gpg --import
    git fetch --tags origin
    git verify-tag <tag>
    git rev-parse '<tag>^{}'

The last command prints the tagged commit, which should match the commit on the GitHub Release page.

## Sparkle updates

Floe checks every update against this public key, which is `SUPublicEDKey` in [`project.yml`](../project.yml):

    hEUA26fN0uTXfnilG4w6FP1zhtaEHVbS7TsUqGW8VsU=

The app reads updates from `https://thaw-app.github.io/Floe/appcast.xml`. The feed itself is served over HTTPS and isn't
signed; the updates it lists are.

## Report a problem

If a check fails on an official release, report it privately under the
[Security Policy](https://github.com/thaw-app/.github/blob/main/.github/SECURITY.md).
