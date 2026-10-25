# SnuggleTemp

SnuggleTemp is a local-first heating-consumption and household-heating-budget tracker. It includes an Android app built with Flutter, monthly consumption charts, an editable advance-payment schedule, annual cost statements, break-even and buffer targets, and an optional weather-adjusted projection.

The project also includes optional Windows/Python tools to export a user's own Techem heating history and calculate budget estimates from local data. The Android app can be used without the Windows exporter; no hosted backend or account operated by this project is required.

## Features

- Monthly heating-consumption history and current-year comparison with the previous year.
- Smooth, shape-preserving chart curves; dotted budget and weather-adjusted projections.
- Editable effective-dated advance payments and annual cost-statement records.
- Local persistence and CSV/JSON import/export workflows.
- Optional weather adjustment using location settings and Open-Meteo data. This is an estimate, not a full-year weather forecast.
- Optional Windows exporter using a locally stored Windows DPAPI-protected Techem session.
- Forecast and schedule regression tests.

## Android app

### Requirements

- Flutter SDK compatible with the version constraint in `app/pubspec.yaml` (Dart 3.9 or newer).
- Android SDK/toolchain configured for Flutter.

### Run and test

```powershell
cd app
flutter pub get
flutter analyze
flutter test
flutter run
```

### Build an APK

```powershell
cd app
.\build_debug.ps1
# or
.\build_release.ps1
```

The build scripts work without private data and produce an app with an empty/local-first starting state. If you intentionally place your own `techem_heating_history.json` and `snuggletemp_settings.local.json` in the repository root, the scripts temporarily bundle them into the APK and remove the temporary asset copies afterward. **An APK built this way contains your personal consumption and financial settings; do not share it publicly.** These files are ignored by Git.

## Optional Windows Techem exporter

The exporter is Windows-only because it uses Windows DPAPI to protect the signed-in session for the current Windows user. It is an optional personal utility, not required by the Android app.

Requirements: Python 3.10+ and the packages in `requirements.txt`.

```powershell
py -3 -m pip install -r requirements.txt
py -3 .\export_techem_heating.py
'py -3 .\forecast_heating_budget.py --baseline-annual-kwh 10000 --heating-basic-eur 200 --heating-variable-eur 1000 --other-costs-eur 800 --annual-advances-eur 2400'
```

The exporter expects you to authenticate to Techem yourself and stores its session only in the ignored local file `techem_auth.dpapi`. Never share this file or the generated consumption exports. The exporter does not bypass authentication. The calculator example uses invented placeholder values; replace them with your own statement figures. The `--year` and `--baseline-year` options default to the current and previous calendar years.

## Data and privacy

- Consumption exports, local settings, DPAPI credentials, logs, bills/OCR documents, generated APKs, and temporary private app assets are excluded from version control.
- App data is stored locally on the device. The optional weather lookup sends the configured location to the chosen weather provider.
- Techem sign-in happens in Techem's own page inside the app. SnuggleTemp does not need your Techem password in a custom form and has no project-operated server.
- Review the source and your local settings before building or sharing an APK. Never commit secrets, session cookies, account identifiers, or personal energy records.

## Weather projection notes

The orange weather-adjusted line estimates consumption using historical seasonal heating-degree-day patterns and available short-range forecast anomalies. It is a scenario estimate for the remaining months, not a claim to know future weather. See [the forecast method](heating_forecast_method.md) and [research notes](docs/research.md).

## Project documentation

- [Architecture](docs/architecture.md)
- [Data model](docs/data-model.md)
- [Design notes](docs/design.md)
- [Research and sources](docs/research.md)
- [Roadmap](docs/roadmap.md)
- [Forecast method](heating_forecast_method.md)

## License and disclaimer

Released under the MIT License; see [LICENSE](LICENSE).

SnuggleTemp is an independent community project and is not affiliated with, endorsed by, or supported by Techem. Techem is a third-party service; its website, API, and authentication behavior may change. Use the exporter and estimates at your own discretion and verify financial decisions against your official statements.