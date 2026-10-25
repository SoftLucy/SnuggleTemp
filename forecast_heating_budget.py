#!/usr/bin/env python3
"""Estimate annual heating costs and remaining monthly kWh targets from local data."""
from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from datetime import date
from pathlib import Path


def read_history(path: Path) -> dict[int, dict[int, float]]:
    history: dict[int, dict[int, float]] = defaultdict(dict)
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            if row.get("service") != "HEATING" or row.get("unit") != "kWh":
                continue
            year_text, month_text = row["period"].split("-")
            history[int(year_text)][int(month_text)] = float(row["amount_kwh"])
    return dict(history)


def estimated_heating_cost(
    annual_kwh: float,
    baseline_annual_kwh: float,
    basic_eur: float,
    variable_eur: float,
) -> float:
    if baseline_annual_kwh <= 0:
        raise ValueError("Baseline annual kWh must be positive.")
    return basic_eur + variable_eur * annual_kwh / baseline_annual_kwh


def max_annual_kwh(
    annual_advances_eur: float,
    desired_buffer_eur: float,
    other_costs_eur: float,
    basic_eur: float,
    baseline_annual_kwh: float,
    variable_eur: float,
) -> float:
    if baseline_annual_kwh <= 0 or variable_eur <= 0:
        raise ValueError("Baseline annual kWh and variable heating cost must be positive.")
    variable_budget = annual_advances_eur - desired_buffer_eur - other_costs_eur - basic_eur
    return max(0.0, variable_budget * baseline_annual_kwh / variable_eur)


def main() -> None:
    current_year = date.today().year
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=Path(__file__).with_name("techem_heating_history.csv"))
    parser.add_argument("--year", type=int, default=current_year, help="target year (default: current year)")
    parser.add_argument("--baseline-year", type=int, default=current_year - 1,
                        help="historical year used to distribute future-month targets (default: previous year)")
    parser.add_argument("--baseline-annual-kwh", type=float, required=True,
                        help="annual heating usage from the reference statement")
    parser.add_argument("--heating-basic-eur", type=float, required=True,
                        help="fixed heating cost from the reference statement")
    parser.add_argument("--heating-variable-eur", type=float, required=True,
                        help="variable heating cost from the reference statement")
    parser.add_argument("--other-costs-eur", type=float, required=True,
                        help="estimated annual non-heating costs")
    parser.add_argument("--annual-advances-eur", type=float, required=True,
                        help="total advances paid for the target year")
    parser.add_argument("--buffer", type=float, default=100.0,
                        help="desired euro buffer after estimated total costs (default: 100)")
    args = parser.parse_args()

    history = read_history(args.csv)
    if args.year not in history:
        raise SystemExit(f"No consumption records found for {args.year}.")
    target_months = history[args.year]
    last_month = max(target_months)
    actual_ytd = sum(target_months.values())
    cost = lambda kwh: estimated_heating_cost(
        kwh, args.baseline_annual_kwh, args.heating_basic_eur, args.heating_variable_eur
    ) + args.other_costs_eur
    zero_target = max_annual_kwh(
        args.annual_advances_eur, 0.0, args.other_costs_eur, args.heating_basic_eur,
        args.baseline_annual_kwh, args.heating_variable_eur,
    )
    buffer_target = max_annual_kwh(
        args.annual_advances_eur, args.buffer, args.other_costs_eur, args.heating_basic_eur,
        args.baseline_annual_kwh, args.heating_variable_eur,
    )
    remaining_zero = max(0.0, zero_target - actual_ytd)
    remaining_buffer = max(0.0, buffer_target - actual_ytd)
    baseline = history.get(args.baseline_year, {})
    future_months = list(range(last_month + 1, 13))
    baseline_future_sum = sum(baseline.get(month, 0.0) for month in future_months)

    print(f"Target year: {args.year}; data through month: {last_month:02d}")
    print(f"Baseline year: {args.baseline_year}")
    print(f"YTD actual: {actual_ytd:,.1f} kWh")
    print(f"Annual advances supplied: €{args.annual_advances_eur:,.2f}")
    print(f"Estimated total cost at baseline usage: €{cost(args.baseline_annual_kwh):,.2f}")
    print(f"Annual kWh ceiling for €0 extra: {zero_target:,.1f}")
    print(f"Remaining kWh budget for €0 extra: {remaining_zero:,.1f}")
    print(f"Annual kWh ceiling for €{args.buffer:,.2f} buffer: {buffer_target:,.1f}")
    print(f"Remaining kWh budget for €{args.buffer:,.2f} buffer: {remaining_buffer:,.1f}")
    if not future_months:
        print("No unreported months remain.")
        return
    if baseline_future_sum <= 0:
        print("No positive baseline consumption for future months; cannot allocate monthly targets.")
        return
    print("\nMonth | Baseline actual (kWh) | €0-extra target (kWh) | Buffer target (kWh)")
    for month in future_months:
        weight = baseline.get(month, 0.0) / baseline_future_sum
        print(f"{month:02d}    | {baseline.get(month, 0.0):>21,.1f} | "
              f"{remaining_zero * weight:>20,.1f} | {remaining_buffer * weight:>18,.1f}")


if __name__ == "__main__":
    main()
