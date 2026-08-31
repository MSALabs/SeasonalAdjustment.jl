# Bundled datasets

Human-readable provenance for `data/*.csv`, duplicating `DatasetInfo`'s own
content (`dataset_info(name)` in Julia) for anyone who opens the repository
and asks where the numbers came from. See `handoff/w9-datasets-handoff.md`
for the full design rationale.

All files are `date,value` CSV: header row, ISO-8601 date (quarterly series
date the first month of the quarter -- Q1→01, Q2→04, Q3→07, Q4→10, matching
[`parse_table`](@ref)'s own `YYYYQQ` convention), `Float64` value, one
observation per row.

## `airline.csv` — International airline passengers

- **Frequency / span / n**: monthly, 1949-01 – 1960-12, 144 observations
- **Units**: thousands of passengers
- **Source**: Box, G.E.P. and Jenkins, G.M. (1976). *Time Series Analysis:
  Forecasting and Control*. Holden-Day. Series G.
- **Licence**: Public domain
- **Kind**: `:published`

Box and Jenkins' Series G, the most recognised series in time series
analysis (base R's `AirPassengers`). Already this package's own verification
baseline (`handoff/verification/airline_baseline/`), so book output and
test fixtures agree by construction. Strongly multiplicative — the
seasonal swing grows with the level, which is why X-13 selects a log
transform. X-13 detects a real, non-obvious additive outlier at May 1951
under this package's own fixture spec (surrounding values 163/172/178 for
Apr/May/Jun — not visually obvious; detection runs on regARIMA residuals
after differencing, not levels). Verified on generation: n=144,
sum=40363, mean=280.2986, matching the canonical `AirPassengers` value.

## `appliance.csv` — Monthly retail sales of household appliance stores

- **Frequency / span / n**: monthly, 1972-07 – 1988-06, 192 observations
- **Units**: unknown (not stated in the source; recorded honestly rather
  than guessed)
- **Source**: U.S. Census Bureau (2015). *X-13ARIMA-SEATS Reference
  Manual*, Version 1.1, Chapter 3, Examples 3.1–3.4.
- **Licence**: Public domain (US federal government work)
- **Kind**: `:published`

Transcribed verbatim from the Census Bureau's own worked example, chosen
by them because its spectrum reveals a trading-day component. December
dominates the seasonal shape (1.52× the annual mean, vs. February's
0.86×) — a retail Christmas peak, and a completely different seasonal
structure from `airline`'s summer peak. Verified on generation: n=192,
sum=248096, mean=1292.1667.

## `appliance_q.csv` — `appliance`, aggregated to quarters

- **Frequency / span / n**: quarterly, 1972-Q3 – 1988-Q2, 64 observations
- **Units**: unknown (same caveat as `appliance`)
- **Source**: derived from `appliance` (itself the Census Bureau's own
  worked example, see above)
- **Licence**: Public domain (US federal government work)
- **Kind**: `:derived` — **not an independently published series**

`appliance`'s 192 months summed into 64 quarters, sums preserved exactly.
Exists to exercise `period=4` — quarterly dates, Q1–Q4 tick labels,
quarterly outlier labels, the quarterly-scaled `seasonal_ma` in
[`filters`](@ref). Weak for anything substantive: aggregation washes out
the trading-day and moving-holiday structure that makes quarterly
adjustment genuinely interesting. A real published quarterly series would
be better and should replace this when one is sourced.

## `iip_india.csv` — India Index of Industrial Production (General)

- **Frequency / span / n**: monthly, 2011-04 – 2026-03, 180 observations
- **Units**: index, base 2011-12 = 100
- **Source**: Ministry of Statistics and Programme Implementation (MOSPI),
  Government of India. Index of Industrial Production, General Index.
- **Licence**: Government of India open data — **exact redistribution
  terms not independently verified this session**. The source handoff
  (`handoff/w9-datasets-handoff.md` §7.2) explicitly left this dataset
  blocked pending a licensing check; this file resolves the *data*
  availability but not that check. Confirm terms before any wider
  publication or redistribution.
- **Kind**: `:published`

The real Indian monthly series this package's own India-calendar layer
(`INDIA_NSE`, `custom_holiday_regressor`) needs a genuine worked example
against. Carries a real, dramatic COVID level shift — April 2020: 54.0,
down from 117.2 in March 2020, the sharpest single-month move in the
series — which also resolves the source handoff's separately-flagged
need (§10.5) for a real level-shift example. The original source file
used a different column/date format (`"date","in.iip.2011.12"` header,
`"Mon YYYY"` dates, quoted fields); normalized to this package's standard
`date,value`/ISO-8601 shape at authoring time so every dataset shares one
reader (`SeasonalAdjustment._read_dataset_csv`).

---

## Outstanding (handoff §10)

Per `handoff/w9-datasets-handoff.md`, still needed and not yet shipped:

- **A series that FAILS its diagnostics** (§10.1) — both current datasets
  adjust cleanly; a deliberately weak/fast-moving synthetic series is
  recommended, labelled `:synthetic`.
- **A near-zero or zero-crossing series** (§10.2) — for comparing
  multiplicative/additive/pseudo-additive modes meaningfully.
- **A series where X-11 and SEATS diverge** (§10.3) — has to be found by
  running both engines over shipped/candidate datasets.
- **A short series** (§10.4) — trivial to construct by truncating an
  existing one; demonstrates the 3-complete-years minimum.
