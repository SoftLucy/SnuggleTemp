# SnuggleTemp architecture

Updated: 2026-10-25

## Product direction

SnuggleTemp will become an Android app for understanding Techem monthly heating consumption, comparing years, estimating year-end consumption and cost, and separating a financial target from a weather-aware forecast.

**Default decision: local-first Flutter app, no backend in the first release.** Add a backend only when a specific requirement needs it. The Android app now uses an in-app Techem WebView for sign-in and requests the portal's rendered heating-history page directly.

## Proposed high-level structure

This is a target layout, not a claim that the Flutter app or backend already exists.

- AGENTS.md — working instructions and project constraints
- README.md — quick start and current state
- docs/ — architecture, research, data model and roadmap
- documents/ — local source bills and OCR; ignored by Git
- app/ — future Flutter project and its tests
- backend/ — optional future Python API
- tests/ — Python calculation tests and sanitized fixtures
- export_techem_heating.py — existing Windows-only manual exporter
- forecast_heating_budget.py — existing reproducible budget calculator
- techem_heating_history.* — local exported data

The existing scripts and their outputs remain at the root until a move can be done with command files and documentation updated together.

## Flutter app layers

Use a small feature-first structure:
- Views render charts, status, forms and tables; no network calls or forecasting formulas.
- ViewModels/controllers coordinate screen state, import/refresh actions and presentation formatting.
- Repositories are the single source of truth for consumption, bills, settings and forecast records.
- Services parse imported files, access local storage and call weather APIs.
- Pure calculation code handles HDD and forecast aggregation. Avoid a separate domain layer until complexity justifies it.

Use immutable models, explicit units, dependency injection, and fakes for tests. Follow Flutter's official architecture guidance without adding unnecessary frameworks.

## Local persistence and import

- Prefer direct Techem refresh: if the WebView session is missing or expired, open the Techem heating page in an in-app WebView and let the user sign in there.
- Read the WebView's Techem session cookie in memory for the portal session check and history request; never copy the password or cookie into SharedPreferences, logs, or app assets.
- Keep CSV/JSON import through Android's system file picker as a fallback.
- Validate rows and merge monthly records idempotently.
- Key monthly records by service, period, source and revision so re-import is idempotent.
- Preserve status, quality, revision, unit and source period where present.
- Keep a local copy of imports and settings. Use SQLite only if structured queries/history become useful; simple preferences can use lightweight settings storage.
- The app must remain useful offline: imported history, previous forecast snapshots, budgets and charts stay local.

## Weather provider boundary

Define a WeatherRepository/provider interface that returns normalized daily mean outdoor temperature plus provenance. Initial candidates are Open-Meteo and DWD Open Data. Keep location configurable and use coordinates selected by the user, not a guessed default.

Each weather value should carry date/timezone, source/provider and endpoint/model, data kind (observation/reanalysis, forecast, or climate normal), retrieval time and a user-selected location identifier. Avoid storing a street address when coordinates are enough.

Cache requests locally, request only needed temperature variables, and avoid polling. Show source and last refresh.

## Forecast separation

Maintain independent outputs:
1. **Budget target:** derived from the monthly advance schedule, non-heating costs, fixed/variable heating assumptions and a fixed €100 buffer scenario. The schedule supports effective-from-month changes; weather never changes the financial ceiling.
2. **Expected consumption:** actual year-to-date kWh plus predicted future monthly kWh.
3. **Weather-aware forecast:** predicted use from historical observations and available forecast weather, with climate/seasonal fallback outside the forecast horizon.
4. **Budget comparison:** projected costs, remaining buffer and any gap between expected use and target.

Never disguise expected use as an allowance. Keep observed values, predictions, targets and uncertainty visually distinct.

## Weather model plan

Start with transparent heating-degree days:

HDD per day = max(0, configurable base temperature − daily mean outdoor temperature).

Aggregate daily HDD into months. A starting candidate near 15.5°C can be tested, but is not a universal constant. Fit a simple model such as monthly kWh = baseline + coefficient × monthly HDD from paired consumption/weather data; do not invent coefficients.

Compare against same-month previous-year and multi-year seasonal baselines. Use held-out/rolling-origin evaluation; track MAE in kWh and signed bias. Keep the weather model only if it improves out-of-sample predictions.

For future months, use observed weather for completed months, forecast weather only within its published horizon, and a documented seasonal/climate fallback beyond it. Replace forecast weather with observations as time passes and retain forecast snapshots for evaluation.

## Optional Python backend

Do not create a backend just to proxy an API call. Consider a small FastAPI backend only for real needs such as cross-device sync, centralized caching, protected server-side credentials, scheduled processing, or shared model runs.

If needed, begin with a versioned JSON REST API and SQLite. Keep local-only mode useful. Never move the Windows DPAPI session into Android or expose WebView session cookies to a backend.
