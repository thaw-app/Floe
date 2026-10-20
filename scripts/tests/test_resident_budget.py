import importlib.util
from pathlib import Path
import unittest
from unittest import mock


spec = importlib.util.spec_from_file_location(
    "resident_budget", Path(__file__).resolve().parents[1] / "check-resident-budget.py"
)
budget = importlib.util.module_from_spec(spec)
spec.loader.exec_module(budget)


class ResidentBudgetTests(unittest.TestCase):
    @staticmethod
    def report(value="29.99"):
        return "\n".join(
            f"RESIDENT {stage} {value} MiB limit=30.0"
            for stage in budget.STAGES
        ) + "\nRESIDENT PASS\n"

    def test_cli_rejects_arbitrary_executables_before_running_anything(self):
        for target in ["/bin/sh", "./malicious/Floe", "release; touch /tmp/unwanted"]:
            with self.subTest(target=target), mock.patch.object(budget, "measure") as measure:
                with mock.patch("sys.argv", ["check-resident-budget.py", target]):
                    with self.assertRaises(SystemExit) as error:
                        budget.main()
                    self.assertEqual(error.exception.code, 2)
                measure.assert_not_called()

    def test_named_targets_only_launch_their_fixed_build_product(self):
        for target, binary in budget.BUILD_PRODUCTS.items():
            with self.subTest(target=target):
                process = mock.Mock(pid=31415, returncode=0)
                process.communicate.return_value = (self.report(), None)
                with mock.patch.object(budget.subprocess, "Popen", return_value=process) as launch:
                    with mock.patch.object(budget.os, "killpg") as kill_group:
                        self.assertTrue(budget.measure(target, 30))
                self.assertEqual(launch.call_args.args[0], [str(binary)])
                self.assertTrue(binary.is_absolute())
                self.assertTrue(binary.is_relative_to(budget.ROOT))
                self.assertEqual(launch.call_args.kwargs["env"]["FLOE_RESIDENT_BENCH"], "30")
                self.assertTrue(launch.call_args.kwargs["start_new_session"])
                kill_group.assert_called_once_with(process.pid, budget.signal.SIGTERM)

    def test_direct_calls_cannot_bypass_the_target_allowlist(self):
        with mock.patch.object(budget.subprocess, "Popen") as launch:
            with self.assertRaises(KeyError):
                budget.measure("/bin/sh", 30)
            launch.assert_not_called()

    def test_invalid_budgets_do_not_start_a_build(self):
        for limit in ["nan", "inf", "0", "-1"]:
            with self.subTest(limit=limit), mock.patch.object(budget, "measure") as measure:
                with mock.patch("sys.argv", ["check-resident-budget.py", "release", limit]):
                    with self.assertRaises(SystemExit) as error:
                        budget.main()
                    self.assertEqual(error.exception.code, 2)
                measure.assert_not_called()

    def test_non_ascii_measurements_are_not_native_benchmark_output(self):
        self.assertFalse(budget.within_budget(self.report("２９.９９"), 30))

    def test_accepts_all_six_measurements(self):
        self.assertTrue(budget.within_budget(self.report(), 30))

    def test_does_not_truncate_fractional_mebibytes(self):
        self.assertFalse(budget.within_budget(self.report("30.01"), 30))

    def test_cannot_pass_without_menu_traversal_settling_or_all_three_exits(self):
        for stage in budget.STAGES:
            with self.subTest(stage=stage):
                truncated = "\n".join(
                    line for line in self.report().splitlines()
                    if not line.startswith(f"RESIDENT {stage} ")
                )
                self.assertFalse(budget.within_budget(truncated, 30))

    def test_menu_allocations_cannot_be_hidden_by_a_passing_cold_measurement(self):
        output = self.report().replace("RESIDENT after-menu 29.99", "RESIDENT after-menu 30.01")
        self.assertFalse(budget.within_budget(output, 30))

    def test_settled_memory_must_still_fit(self):
        output = self.report().replace("RESIDENT settled 29.99", "RESIDENT settled 30.01")
        self.assertFalse(budget.within_budget(output, 30))

    def test_a_printed_pass_without_measurements_is_not_success(self):
        self.assertFalse(budget.within_budget("RESIDENT PASS\n", 30))

    def test_failure_cannot_pass_on_memory_measurements_alone(self):
        self.assertFalse(budget.within_budget(self.report().replace("RESIDENT PASS", "RESIDENT FAIL"), 30))
