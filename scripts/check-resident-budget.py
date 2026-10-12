#!/usr/bin/env python3
"""Check resident footprint at startup, after menu queries and after dismissal.

Usage: python3 scripts/check-resident-budget.py path/to/Floe [MiB, default 30]
The three foreground windows render offscreen. No installed app is replaced.
"""

import argparse
import math
import os
import re
import signal
import subprocess
import sys


def within_budget(output, limit):
    rows = re.findall(r"^RESIDENT (cold|after-menu|dismissed-[123]|settled) ([0-9]+\.[0-9]+) MiB", output, re.M)
    return (
        [stage for stage, _ in rows] == ["cold", "after-menu", "dismissed-1", "dismissed-2", "dismissed-3", "settled"]
        and all(float(value) <= limit for _, value in rows)
        and "RESIDENT PASS" in output.splitlines()
    )


def measure(binary, limit, timeout=120):
    environment = dict(os.environ, FLOE_RESIDENT_BENCH=str(limit))
    process = subprocess.Popen(
        [binary], env=environment, stdout=subprocess.PIPE,
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary")
    parser.add_argument("limit", type=float, nargs="?", default=30)
    args = parser.parse_args()
    if not math.isfinite(args.limit) or args.limit <= 0:
        parser.error("the budget must be a positive finite number")
    try:
        passed = measure(args.binary, args.limit)
    except OSError as error:
        print(f"::error::Could not run the resident benchmark: {error}")
        return 1
    if not passed:
        print("::error::Resident memory or process-lifecycle budget failed.")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
