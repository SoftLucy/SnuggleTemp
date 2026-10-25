# SnuggleTemp roadmap

Updated: 2026-10-25

## Phase 0 — stabilize current tools

- [x] Preserve the manual Techem exporter and existing CSV/JSON format.
- [x] Preserve the reproducible budget calculator.
- [x] Document project instructions, architecture direction, data model and weather/backend research.
- [x] Add initial automated Python tests for budget math and CSV parsing.
- [ ] Add sanitized fixture files for broader parser/regression coverage; never commit real bills, auth state or private exports.
- [ ] Confirm actual 2026 advance payments from rent/bank records when convenient.

## Phase 1 — Flutter foundation

- [x] Create the Flutter Android project under app/.
- [x] Set up formatting, analyzer checks, a widget smoke test and a successful Android debug APK build.
- [ ] Split consumption, budget and forecast records into testable model/repository classes.
- [x] Add CSV/JSON import and merge by month as a fallback.
- [x] Add direct Techem fetching with an in-app sign-in WebView and session validation.
- [x] Build a dashboard with year-to-date consumption, year comparison and missing-data state.
- [x] Add a non-cumulative monthly chart with actuals, break-even target, €100 buffer and a weather-aware series.
- [x] Add an effective-dated monthly advance-payment schedule that recalculates annual advances and both budget scenarios.
- [x] Persist readings, assumptions and statement entries locally.

## Phase 2 — weather-aware forecast

- [x] Add user-controlled latitude/longitude settings; no inferred home location.
- [x] Fetch historical daily temperatures and short-range forecast from Open-Meteo; display attribution.
- [x] Derive monthly HDD and use seasonal fallback outside the forecast horizon.
- [ ] Add a replaceable weather-provider interface and response caching.
- [ ] Validate on held-out months/years; record MAE and bias against seasonal baselines.
- [x] Keep budget targets separate from the weather-adjusted expected-use line.
- [ ] Save forecast snapshots and score them when actual Techem data arrives.

## Phase 3 — cost model refinement

- [x] Keep advance payments and effective dates editable.
- [ ] Show source year and provenance for each cost assumption.
- [x] Keep a fixed €100 buffer scenario separate from the break-even scenario.
- [ ] Recalibrate from the next annual statement rather than silently carrying costs forward.
- [ ] Keep portal EED kWh and billed allocator units distinct.

## Phase 4 — decide whether a backend is warranted

Do not begin until a requirement justifies it. Possible triggers are cross-device sync/backup, shared data across clients, centralized caching/scheduled processing, or a model that needs shared execution.

If justified:
- [ ] Design a small versioned FastAPI REST API.
- [ ] Use SQLite for small persistence needs.
- [ ] Add authentication only if remote access is actually required.
- [ ] Keep local-only mode usable and do not expose the Techem DPAPI session.

## Phase 5 — validation and release

- [ ] Test with sanitized examples and the user's real import locally.
- [ ] Test empty, malformed, duplicate, revised and zero-value months.
- [ ] Verify offline behavior, timezones, attribution and source labels.
- [ ] Build and install a debug APK on the Pixel 7 Pro.
- [ ] Check screen-reader labels, font scaling, contrast and chart legends.
- [ ] Document release/build steps and export/backup behavior.
