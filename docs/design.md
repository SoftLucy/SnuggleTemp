# SnuggleTemp app design

Updated: 2026-10-25

## Design direction

Build a calm, modern, mobile-first dashboard that makes one decision easy: how much heating is left for each remaining month, and how does expected use compare with the financial goal?

- Soft off-white page background, white rounded cards, dark ink text, purple primary action/goal card.
- One non-cumulative monthly line chart. Do not accumulate kWh across months.
- Month labels Jan–Dec; actuals remain solid and stop at the last reported month; forecast lines occupy only months that still need a forecast.
- Consistent series: previous-year actual (blue), current-year actual (ink), break-even / €0 balance (mint), €100 safety-buffer scenario (purple dashed), weather-aware estimate (amber dashed).
- Tapping chart points reveals month and kWh. Legends remain visible; don't rely on colour alone in later accessibility pass.
- Two compact headline metrics: remaining kWh to break even and remaining kWh with a €100 buffer.
- Advance-payment settings use an effective-dated schedule; each amount applies until the next change. The schedule determines total advances for the year, and the app calculates break-even and configurable-buffer lines automatically.
- A billing-statement editor stores three user-entered figures for each year: total costs, advances paid and final Nachzahlung/Guthaben. The previous year's total is used with the known heating-cost components to infer the remaining non-heating costs.
- Data and assumptions are stored on-device. No account, analytics or cloud backend.

## Similar projects reviewed

### Energietracker

Repository: https://github.com/Bingerminger/energietracker

Useful ideas: bills and contracts alongside readings, weather-adjusted analysis, clear country-specific assumptions, in-app explanations/glossary, and a lightweight approach that does not require a database server. SnuggleTemp is narrower and should not copy the broader energy-contract/CO₂ scope.

### Nexo (Flutter personal finance)

Repository: https://github.com/Chere3/nexo

Useful ideas: Material 3, dashboard-oriented budget visibility, CSV import/export, local persistence, and feature-first Flutter structure. SnuggleTemp borrows the visual clarity and local-first pattern, not its account/transfer/AI features.

## Technical choices

- Flutter Material 3; fl_chart for custom monthly line series; shared_preferences for the small initial local settings/history store.
- Use a local repository/data layer; calculation logic remains separate from visual presentation as the app grows.
- CSV/JSON import merges monthly records by YYYY-MM, replacing changed revisions instead of duplicating months.
- Android direct refresh checks the existing WebView session, opens the Techem heating page in an in-app WebView if sign-in is needed, and requests the history page with the session cookie held in memory. Passwords and cookies are not copied into app preferences or a backend. CSV/JSON import remains a fallback. The Windows DPAPI exporter stays separate.
- Weather is opt-in: user enters latitude/longitude; Open-Meteo supplies historical temperature and a short forecast. Historical monthly heating-degree-days provide a seasonal reference, with forecast HDD replacing the normal contribution for days in the short forecast horizon. Months beyond the forecast horizon fall back to the previous-year seasonal profile.
- The first weather model is a heuristic, not a calibrated building model. Keep it visually distinct from budget limits, and validate it against future readings before trusting it for decisions.
- Open-Meteo attribution is shown in the UI. Review current API terms before any public/commercial release.

## Known first-version boundaries

- Techem direct fetching depends on the portal's current Next.js page payload and route shape. If Techem changes those, the parser needs an update; the manual CSV/JSON import remains a fallback.
- The current bill fields are manually entered and are not OCR-verified.
- Forecast confidence intervals and forecast-history scoring are future improvements.
- The starter consumption asset is generated locally from the private export for a personal APK and is ignored by Git. Never commit it.
