#!/usr/bin/env bash
# Asks for each GitHub Actions secret Floe's workflows use and stores it on
# thaw-app/Floe with gh. The signing secrets go in the "prod" environment, so
# only jobs approved for that environment can read them. Press Return to skip
# one; skipped secrets are left as they are. Input is hidden and never written to disk. Answer with @ and a path
# to read a value from a file, or with @@ for a value that itself starts with @.
#
# Usage:
#   ./scripts/set-secrets.sh          # ask for every secret
#   ./scripts/set-secrets.sh --list   # show what is set on GitHub now
set -euo pipefail

REPO="thaw-app/Floe"

# name|environment (empty for a repository secret)|needed|what it is and where to get it
SECRETS=(
    "APPLE_APPLICATION_CERT|prod|signing|Your Developer ID Application certificate with its private key, as a base64 .p12. Export it from Keychain Access (My Certificates, right-click, Export) and answer here with @ and the file's path, for example @~/Desktop/DeveloperID.p12; the script encodes it."
    "APPLE_APPLICATION_CERT_PASSWORD|prod|signing|The password you chose when exporting that .p12."
    "APPLE_TEAM_ID|prod|signing|Your 10-character Apple Developer team ID, from developer.apple.com/account under Membership details."
    "APPLE_ID|prod|notarization|The Apple ID email of the developer account that notarizes the app."
    "APPLE_ID_PASSWORD|prod|notarization|An app-specific password for that Apple ID, created at account.apple.com under Sign-In and Security, App-Specific Passwords. Not your account password."
    "SPARKLE_ED25519_PRIVATE_KEY|prod|updates|The private half of the Sparkle EdDSA key that signs update ZIPs and the appcast. Generate the pair once: after swift build, run .build/artifacts/sparkle/Sparkle/bin/generate_keys --account floe. It stores the private key in your login Keychain and prints the public key, which goes in SUPublicEDKey in project.yml. Then export the private key with generate_keys --account floe -x ~/floe-sparkle.key, answer here with @~/floe-sparkle.key, and delete that file. Keep the Keychain item: a lost key means installed copies can no longer update."
    "SONAR_TOKEN||analysis|Token for the SonarQube Cloud scan in CI. Create it at sonarcloud.io under My Account, Security. It stays a repository secret because the scan runs on every push and pull request."
    "SCORECARD_READ_TOKEN||optional|Fine-grained personal access token for the Scorecard workflow, so its Branch-Protection check can read the repository's settings. Create it at github.com/settings/personal-access-tokens with access to thaw-app/Floe and read-only Administration. Without it the workflow falls back to its own token and that one check is less complete."
)

command -v gh >/dev/null 2>&1 || {
    echo "gh is not installed (brew install gh)" >&2
    exit 1
}

list_secrets() {
    echo "Repository secrets:"
    gh secret list -R "$REPO"
    echo "prod environment secrets:"
    gh secret list -R "$REPO" --env prod
}

if [[ "${1:-}" == "--list" ]]; then
    list_secrets
    exit 0
fi

for entry in "${SECRETS[@]}"; do
    IFS='|' read -r name environment needed description <<<"$entry"
    target=(-R "$REPO")
    [[ -n "$environment" ]] && target+=(--env "$environment")
    printf '\n\033[1m%s\033[0m (%s%s)\n%s\n' "$name" "$needed" "${environment:+, $environment environment}" "$description"
    read -r -s -p "Value (Return to skip): " value
    echo
    if [[ -z "$value" ]]; then
        echo "Skipped."
        continue
    fi
    # "@path" reads the value from a file; a .p12 is base64-encoded on the way. "@@" stands for a value that starts with @.
    if [[ "$value" == @@* ]]; then
        printf '%s' "${value#@}" | gh secret set "$name" "${target[@]}"
    elif [[ "$value" == @* ]]; then
        file="${value#@}"
        file="${file/#\~/$HOME}"
        [[ -f "$file" ]] || {
            # The path stays unprinted: it was typed hidden, and may be a mistyped secret.
            echo "No file at that path. $name was not set." >&2
            continue
        }
        if [[ "$file" == *.p12 ]]; then
            base64 -i "$file" | tr -d '\n' | gh secret set "$name" "${target[@]}"
        else
            gh secret set "$name" "${target[@]}" <"$file"
        fi
    else
        printf '%s' "$value" | gh secret set "$name" "${target[@]}"
    fi
    unset value
done

echo
list_secrets
