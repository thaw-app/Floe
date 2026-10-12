import importlib.util
from pathlib import Path
import unittest


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
            for stage in ["cold", "after-menu", "dismissed-1", "dismissed-2", "dismissed-3", "settled"]
        ) + "\nRESIDENT PASS\n"

    def test_accepts_all_six_measurements(self):
        self.assertTrue(budget.within_budget(self.report(), 30))

    def test_does_not_truncate_fractional_mebibytes(self):
        self.assertFalse(budget.within_budget(self.report("30.01"), 30))

    def test_cannot_pass_without_menu_traversal_settling_or_all_three_exits(self):
        for stage in ["cold", "after-menu", "dismissed-1", "dismissed-2", "dismissed-3", "settled"]:
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
