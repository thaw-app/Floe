#!/usr/bin/env python3
"""Exercise devrun's signing branches without building, signing, or installing an app."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
MOCK = r'''#!/usr/bin/env bash
set -eu
name=${0##*/}
printf '%s\n' "$name $*" >> "$TEST_LOG"
case "$name" in
    security)
        if [[ "$1" == "find-identity" ]]; then
            printf '%s\n' "$TEST_IDENTITIES"
        else
            printf '%s%s%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>Entitlements</key><dict><key>com.apple.application-identifier</key><string>' "$TEST_APPLICATION" '</string></dict></dict></plist>'
        fi
        ;;
    lipo) echo 'arm64 x86_64' ;;
    xcodebuild) echo 'BUILD SUCCEEDED' ;;
    pgrep) exit 1 ;;
    bun|xcodegen|codesign|ditto|rm) : ;;
    *) exit 99 ;;
esac
'''


class DevRunSigningTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="floe-devrun-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for folder in (
            "scripts", "runtime", "Resources", "tools", "Vendor/FloeRust/rust/src",
            "Vendor/FloeRust/include", ".build/xcode/Build/Products/Release/Floe.app/Contents",
        ):
            (self.root / folder).mkdir(parents=True, exist_ok=True)
        source = Path(os.environ.get("FLOE_DEVRUN_UNDER_TEST", ROOT / "scripts/devrun.sh"))
        shutil.copyfile(source, self.root / "scripts/devrun.sh")
        shutil.copyfile(ROOT / "Resources/Floe-iCloud.entitlements", self.root / "Resources/Floe-iCloud.entitlements")
        (self.root / "Vendor/FloeRust/rust/Cargo.toml").touch()
        (self.root / "Vendor/FloeRust/Frameworks/CFloeRust.xcframework/macos").mkdir(parents=True)
        (self.root / "profile.provisionprofile").touch()
        mock = self.root / "tools/mock"
        mock.write_text(MOCK)
        mock.chmod(0o755)
        for tool in ("security", "lipo", "xcodebuild", "pgrep", "bun", "xcodegen", "codesign", "ditto", "rm"):
            (self.root / "tools" / tool).symlink_to(mock)
        self.log = self.root / "commands.log"

    def run_script(self, *arguments, identities="", identity=None, application="ABCDE12345.org.thaw.floe"):
        environment = os.environ.copy()
        environment.pop("FLOE_SIGN_IDENTITY", None)
        environment.update({
            "PATH": f"{self.root / 'tools'}:/usr/bin:/bin:/usr/sbin:/sbin",
            "FLOE_PROVISIONING_PROFILE": str(self.root / "profile.provisionprofile"),
            "TEST_LOG": str(self.log),
            "TEST_IDENTITIES": identities,
            "TEST_APPLICATION": application,
            "TMPDIR": str(self.root),
        })
        if identity is not None:
            environment["FLOE_SIGN_IDENTITY"] = identity
        result = subprocess.run(
            ["bash", str(self.root / "scripts/devrun.sh"), "--no-launch", *arguments],
            env=environment, capture_output=True, text=True, timeout=10,
        )
        return result, self.log.read_text()

    def test_icloud_with_only_a_developer_id_certificate(self):
        result, commands = self.run_script("--icloud", identities='1) DISTRIBUTION "Developer ID Application: Test (TEAM)"')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("--sign DISTRIBUTION", commands)
        self.assertTrue((self.root / ".build/xcode/Build/Products/Release/Floe.app/Contents/embedded.provisionprofile").exists())

    def test_normal_build_without_certificates_stays_ad_hoc(self):
        result, commands = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("stays ad hoc", result.stdout)
        self.assertNotIn("codesign ", commands)

    def test_explicit_icloud_identity_is_used_without_discovery(self):
        result, commands = self.run_script("--icloud", identity="EXPLICIT")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("--sign EXPLICIT", commands)
        self.assertNotIn("security find-identity", commands)

    def test_missing_distribution_identity_reports_the_reason(self):
        result, _ = self.run_script("--icloud")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No Developer ID Application certificate", result.stderr)

    def test_a_team_that_is_no_team_identifier_is_refused_before_sed(self):
        result, _ = self.run_script("--icloud", identity="EXPLICIT", application="A/e w/x.org.thaw.floe")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("is not a team identifier", result.stderr)


if __name__ == "__main__":
    unittest.main()
