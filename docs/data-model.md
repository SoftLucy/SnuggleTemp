# SnuggleTemp data model

Updated: 2026-10-25

## Principles
- Store units explicitly; do not mix Techem EED kWh with annual-statement allocator units.
- Preserve source metadata and original records during import.
- Use ISO year-month keys (YYYY-MM).
- Distinguish missing data from a reported zero.
- Keep personal source documents and raw exports local.

## Core records

### MonthlyConsumption
- period: ISO year-month, e.g. 2026-09
- service: HEATING (add other services only if explicitly available)
- amount and unit, preserving the source unit
- status, nullable quality, revision number and source timestamp
- source, local import timestamp and optional source-file digest

### AdvancePaymentChange
- target year
- effective-from month (1–12)
- monthly advance amount in EUR

A schedule is an ordered list of changes. Each amount applies from its effective month through the month before the next change. Sum the twelve monthly values to get annual advances.

### CostAssumptions
- fixed/basic heating component and variable component from the selected reference bill
- other operating costs and source year
- fixed €100 buffer scenario alongside break-even (zero balance)
- provenance and last-confirmed date for each cost input

The user edits the payment schedule rather than a separate savings target. Recalculate break-even and buffer kWh whenever a payment amount or effective month changes. Do not silently roll last year's rates into a new billing year.

### DailyWeather
- local calendar date and timezone
- daily mean outdoor temperature in °C; optionally min/max
- provider, endpoint/model and retrieval timestamp
- data kind: observation/reanalysis, forecast, or climate normal
- user-selected location identifier; avoid storing a street address when coordinates suffice

### MonthlyForecast
- creation time and target month
- model/version and configuration (base temperature, coefficients, fallback)
- predicted kWh and optional uncertainty interval
- weather provenance and data kind
- actual kWh when later reported, plus error metrics

Keep forecast snapshots immutable so forecast quality can be evaluated later.

### BillingStatement
- year, billing period, totals and advance totals
- heating/basic/variable components where available
- local source-document reference and extraction notes
- explicit distinction between invoice allocator units and portal EED kWh

## Import behavior
1. Parse into temporary records.
2. Validate period, service, amount, unit and duplicates.
3. Present added/changed/unchanged counts.
4. Commit atomically only after confirmation.
5. Never interpret a missing month as zero consumption.
6. Re-importing the same file must not duplicate records.
