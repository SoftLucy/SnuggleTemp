# SnuggleTemp technical research

Updated: 2026-10-25

## Recommendation

Build the first usable version as a **local-first Flutter Android app**. Fetch Techem heating history directly using a user-authenticated in-app WebView session, keep CSV/JSON import as a fallback, store readings and payment assumptions locally, show consumption/budget charts, and fetch weather through a replaceable provider service. Keep the current Windows exporter separate. Do not add a Python backend until sync, server-side caching, scheduled work or protected credentials create a concrete need.

## Weather source comparison

### Open-Meteo — initial prototype candidate

Official references:
- Forecast API: https://open-meteo.com/en/docs
- Historical Weather API: https://open-meteo.com/en/docs/historical-weather-api
- Historical Forecast API: https://open-meteo.com/en/docs/historical-forecast-api
- Climate API: https://open-meteo.com/en/docs/climate-api
- Terms: https://open-meteo.com/en/terms
- Pricing: https://open-meteo.com/en/pricing

Capabilities:
- Forecast API exposes hourly temperature and forecast horizons up to about 16 days, depending on options.
- Historical weather/reanalysis extends back decades. ERA5/ERA5-Land are candidates for consistent historical series.
- Archived forecasts from around 2022 onward can help evaluate what a forecast would have predicted at the time.
- Climate-model data offers longer-range climate context; it is not a deterministic forecast for a specific future month.

Why it fits:
- Simple HTTPS/JSON, broad coverage, no key required for the free non-commercial service.
- Daily mean temperature can be derived from hourly temperature or requested where supported.
- Straightforward to implement behind a provider interface.

Licensing/operations:
- The free API is for non-commercial applications and has rate limits. Commercial distribution requires the appropriate subscription/licence.
- Attribute displayed data with “Weather data by Open-Meteo.com” and link the CC BY 4.0 licence.
- Recheck terms before distributing or changing the app's use.
- Do not fetch on every chart redraw. Cache by location/date/provider and refresh deliberately.
- Check which historical/climate endpoints are included in the chosen tier before relying on them in a released product.

### DWD Open Data — strong Germany-specific alternative

Official historical hourly temperature directory:
https://opendata.dwd.de/climate_environment/CDC/observations_germany/climate/hourly/air_temperature/historical/

DWD publishes station-based historical hourly temperature archives with station descriptions and date coverage. This is a useful independent source for Germany-focused analysis and validation. It is less convenient for a first Android prototype than a small JSON API because the app or a preprocessing tool must select a station, download archives and parse DWD formats. If used, select the station based on the user's chosen location and coverage; do not hardcode a guessed station.

### Provider decision

1. Implement Open-Meteo as the first adapter for a personal/non-commercial prototype.
2. Keep normalized weather models provider-neutral so DWD or a paid source can be added later.
3. Use a consistent historical series to fit/validate the consumption model; separately evaluate archived forecasts for near-term prediction.
4. Store attribution, source and retrieval metadata with displayed weather and saved forecasts.

## Forecasting approach

### Keep the questions separate

- **Expected consumption:** what is likely given actual readings, weather and historical behavior?
- **Budget target:** what consumption/cost fits the advances and selected buffer?

Cold weather may raise expected use and signal a likely budget overshoot. It must not move the break-even financial ceiling.

### Step 1 — simple baselines first

Compare any weather model with:
- same month in the previous year;
- multi-year average for the same calendar month;
- optionally a weighted recent-year seasonal profile.

The current Techem series is monthly, so start at monthly resolution. Do not start with machine learning or a complex building simulation.

### Step 2 — heating degree days (HDD)

For each day:

HDD = max(0, base temperature − daily mean outdoor temperature).

Sum daily HDD into months. Make base temperature configurable; a candidate near 15.5°C is only a starting value to test, not a universal constant. Heating system, internal gains, ventilation, solar gain, occupancy, setpoint and building envelope all affect the relationship.

A first model can be:

monthly kWh = baseline + kWh-per-HDD × monthly HDD.

Fit the coefficients from paired monthly Techem readings and local historical temperatures. Do not invent coefficients. If data are insufficient or validation is weak, use the seasonal baseline.

### Step 3 — forecast horizon

- Completed months: use observed/reanalysis weather.
- Near-term future: use available forecast weather.
- Farther months: use a seasonal baseline, climate normals, or historical weather scenarios.
- Label each segment so observed weather, forecast weather and longer-range normals are distinguishable.
- Store forecast snapshots; score them when Techem publishes the actual monthly reading.

### Step 4 — validate

Use rolling-origin or leave-one-year-out validation where feasible. Track:
- mean absolute error in kWh;
- average signed error/bias;
- error by month/season;
- performance against the same-month and seasonal baselines.

With only a few years of monthly consumption, model complexity should stay low. Make the weather model the default only if it consistently beats the simpler baseline on held-out periods. Avoid percentage error around zero/summer readings.

### Cost mapping

Keep the existing cost calculator as a distinct, editable scenario model. Show source bill/year for fixed and variable components, effective-dated monthly advance amounts and the fixed €100-buffer scenario. Do not imply portal EED kWh are exactly the same units used in the final annual statement.

As future statements arrive, recalibrate cost assumptions from actual billed costs. The weather model predicts kWh; the cost model estimates euros.

## Flutter architecture research

Flutter's official architecture guide recommends separating views, view models, repositories and services, with repositories as the data source of truth. It also recommends keeping business logic out of widgets, immutable models, dependency injection and tests for each layer.

References:
- https://docs.flutter.dev/app-architecture/guide
- https://docs.flutter.dev/app-architecture/recommendations
- https://docs.flutter.dev/app-architecture/design-patterns/offline-first

Apply proportionately:
- feature-first folders;
- thin view/view-model layer;
- repositories for local consumption, budget assumptions and weather;
- services for file parsing, local storage and provider HTTP requests;
- pure calculation functions with unit tests;
- offline-first history and charts;
- no separate domain/use-case layer until forecasting logic benefits from it.

Choose a maintained Flutter chart package only after defining chart interactions: actual/target/forecast lines, monthly bars, uncertainty band and tap-to-inspect. Keep chart widgets presentation-only.

## Techem direct refresh and in-app login

The existing Windows exporter establishes the relevant portal contract: `https://mieter.techem.de/api/auth/session` validates the NextAuth session, and the `/consumptions/heating/YYYY-MM` server-rendered page contains the complete monthly EED heating history. The Android client follows that flow using the WebView's own login session. It does not ask for credentials in a custom form or persist the session cookie in app preferences; the cookie is passed only in memory to the session/history requests, with redirects disabled to avoid forwarding it to another host. The narrow parser fails closed when the expected record shape is missing, and CSV/JSON import remains the fallback if Techem changes the portal.

The official [`webview_flutter`](https://pub.dev/packages/webview_flutter) plugin wraps Android WebView; version 4.14.0 added cookie retrieval, and the current release supports Android SDK 24+. Keep the package current and verify its cookie API when upgrading.

## Is a Python backend needed?

### Not for version 1

The Android app can use its in-app WebView for Techem sign-in, pass the session cookie only in memory to validate the portal session and fetch the heating-history page, store history/settings locally, call a weather JSON API directly, run forecasts locally and work offline with cached data. Keep CSV/JSON import as a fallback.

### Add one only for a real need

FastAPI becomes useful for cross-device sync, centralized caching/scheduled weather updates, shared model calculations, or credentials that must not be placed in the Android app. If added, start with a small versioned REST API and SQLite for compact data. Do not add PostgreSQL, Docker or a service stack by default.

The Windows DPAPI exporter remains a separate manual tool. Do not move its DPAPI-encrypted session token to Android or expose it as a web service. Android uses only the WebView's own Techem login session; never persist its session cookie in preferences/assets/logs or send it to a backend.

## Security and privacy

- Bills, OCR, usage history, location and credentials are private.
- Never commit techem_auth.dpapi, PDFs, OCR output or personal exports.
- Keep location explicit and user-controlled; avoid telemetry/accounts in the first version.
- Use WebViewCookieManager only to access the signed-in Techem session; keep cookies in memory for direct requests and never log them.
- Show the weather provider's required attribution.
- Validate imported files and never silently replace history.

## References

- Flutter architecture guide: https://docs.flutter.dev/app-architecture/guide
- Flutter architecture recommendations: https://docs.flutter.dev/app-architecture/recommendations
- Flutter offline-first pattern: https://docs.flutter.dev/app-architecture/design-patterns/offline-first
- Flutter WebView package and cookie-manager API: https://pub.dev/packages/webview_flutter
- Techem tenant portal: https://mieter.techem.de/
- Open-Meteo Forecast API: https://open-meteo.com/en/docs
- Open-Meteo Historical Weather API: https://open-meteo.com/en/docs/historical-weather-api
- Open-Meteo Historical Forecast API: https://open-meteo.com/en/docs/historical-forecast-api
- Open-Meteo Climate API: https://open-meteo.com/en/docs/climate-api
- Open-Meteo Terms: https://open-meteo.com/en/terms
- Open-Meteo pricing/licensing: https://open-meteo.com/en/pricing
- DWD historical hourly temperature directory: https://opendata.dwd.de/climate_environment/CDC/observations_germany/climate/hourly/air_temperature/historical/
