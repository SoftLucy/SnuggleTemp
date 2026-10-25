"""Regression tests for the configurable budget calculator."""
import csv
import tempfile
import unittest
from pathlib import Path

import forecast_heating_budget as budget


class BudgetModelTests(unittest.TestCase):
    def test_heating_cost_uses_supplied_baseline_assumptions(self):
        self.assertAlmostEqual(budget.estimated_heating_cost(12_000, 10_000, 200, 1_000), 1_400)

    def test_annual_kwh_ceiling_for_break_even(self):
        self.assertAlmostEqual(budget.max_annual_kwh(2_400, 0, 800, 200, 10_000, 1_000), 14_000)

    def test_annual_kwh_ceiling_for_buffer(self):
        self.assertAlmostEqual(budget.max_annual_kwh(2_400, 100, 800, 200, 10_000, 1_000), 13_000)

    def test_history_reader_filters_service_and_unit(self):
        rows = [
            {"period": "2031-01", "service": "HEATING", "unit": "kWh", "amount_kwh": "100.5"},
            {"period": "2031-02", "service": "HOT_WATER", "unit": "kWh", "amount_kwh": "20"},
            {"period": "2031-03", "service": "HEATING", "unit": "MJ", "amount_kwh": "30"},
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "history.csv"
            with path.open("w", newline="", encoding="utf-8") as stream:
                writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
                writer.writeheader()
                writer.writerows(rows)
            history = budget.read_history(path)
        self.assertEqual(history, {2031: {1: 100.5}})


if __name__ == "__main__":
    unittest.main()
