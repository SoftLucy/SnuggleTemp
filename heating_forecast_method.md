# Heating forecast method

This document describes the model implemented by the optional command-line budget calculator and the Android chart. It intentionally contains no household-specific consumption, tariff, or payment figures.

## Inputs

Use values from your own annual statement and payment schedule:

- Annual reference heating consumption in kWh.
- Fixed/basic heating cost and variable/consumption-dependent heating cost.
- Estimated non-heating operating costs.
- Total advances paid for the target year.
- Monthly historical consumption used to distribute the remaining target across future months.

The Python calculator requires these financial assumptions as command-line arguments rather than embedding anyone's household figures in the source. Its target year defaults to the current calendar year and its allocation baseline defaults to the previous calendar year; both can be overridden.

## Cost estimate

Assuming the variable portion scales linearly with heating consumption:

`estimated heating cost = fixed heating cost + variable heating cost × (estimated annual kWh / reference annual kWh)`

`estimated total cost = estimated heating cost + estimated non-heating operating costs`

For an advance-payment total `A` and desired end-of-year buffer `B`:

`variable heating budget = A − B − non-heating costs − fixed heating cost`

`annual kWh ceiling = max(0, variable heating budget × reference annual kWh / reference variable heating cost)`

The remaining allowance is the annual ceiling minus consumption already recorded for the target year, clamped to zero.

## Monthly allocation

The remaining allowance is distributed among future months in proportion to those months' consumption in the selected baseline year. This gives a seasonal allocation, not a prediction of exact weather or exact usage.

## Weather-aware Android line

The optional weather-aware line scales a historical seasonal heating-degree-day baseline using the available short-range forecast anomaly. Weather data does not provide a reliable daily forecast for the entire remaining year; months outside the short-range forecast use the historical seasonal baseline. The resulting line is an estimate/scenario, not a promise or an official billing calculation.

## Limitations

- The linear cost model assumes the reference tariff structure remains representative.
- Fixed costs, prices, taxes, allocation rules, and payment schedules can change between billing periods.
- Missing or incomplete monthly readings affect both year-to-date totals and seasonal allocation.
- Verify all financial decisions against the official statement and actual advance schedule.
