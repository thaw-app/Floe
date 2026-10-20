#!/usr/bin/env python3
"""Check Floe's footprint at startup, after menu queries, with the launcher shown and closed, after a trim and settled.

Usage: python3 scripts/check-resident-budget.py {release,ci,signed,swiftpm} [MiB, default 150]
Only known repository build products can run. The launcher renders
offscreen. No installed app is replaced.
"""

import argparse
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
BUILD_PRODUCTS = {
    "release": ROOT / ".build/xcode/Build/Products/Release/Floe.app/Contents/MacOS/Floe",
    "ci": ROOT / "Build/Build/Products/Debug/Floe.app/Contents/MacOS/Floe",
    "signed": ROOT / ".build/resident-signed/Floe.app/Contents/MacOS/Floe",
    "swiftpm": ROOT / ".build/debug/Floe",
}


# The order the benchmark prints its measurements in.
STAGES = ["cold", "after-menu"] + [f"{state}-{cycle}" for cycle in (1, 2, 3) for state in ("shown", "dismissed")] + ["trimmed", "settled"]


def within_budget(output, limit):
    """Require every lifecycle stage in order and a successful native verdict."""
    rows = re.findall(r"^RESIDENT (cold|after-menu|shown-[123]|dismissed-[123]|trimmed|settled) (\d+\.\d+) MiB", output, re.M | re.ASCII)
    return (
        [stage for stage, _ in rows] == STAGES
        and all(float(value) <= limit for _, value in rows)
        and "RESIDENT PASS" in output.splitlines()
    )


def measure(target, limit, timeout=120):
    """Run an allowlisted build product and clean up only its process group."""
    binary = BUILD_PRODUCTS[target]
    environment = dict(os.environ, FLOE_RESIDENT_BENCH=str(limit))
    process = subprocess.Popen(
        [str(binary)], env=environment, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, start_new_session=True,
    )
    try:
        output, _ = process.communicate(timeout=timeout)
        print(output, end="")
        return process.returncode == 0 and within_budget(output, limit)
    except subprocess.TimeoutExpired:
        print("::error::Resident benchmark timed out.")
        return False
    finally:
        # Only this benchmark's session, including any extension hosts it started.
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()


def main():
    """Reject unknown build targets and invalid budgets before starting a process."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=BUILD_PRODUCTS)
    parser.add_argument("limit", type=float, nargs="?", default=150)
    args = parser.parse_args()
    if not math.isfinite(args.limit) or args.limit <= 0:
        parser.error("the budget must be a positive finite number")
    try:
        passed = measure(args.target, args.limit)
    except OSError as error:
        print(f"::error::Could not run the resident benchmark: {error}")
        return 1
    if not passed:
        print("::error::Resident memory or process-lifecycle budget failed.")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
