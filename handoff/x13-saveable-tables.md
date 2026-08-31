# X-13ARIMA-SEATS Saveable Output Tables — Reference

Authoritative catalogue of every table X-13ARIMA-SEATS can write via a `save`
argument. **Commit this file to the repository.** It exists so no future session
has to guess a table code or a save keyword.

## Provenance

Cross-compiled from two primary sources, not from recall:

- **`christophsax/seasonal`** `noinst/specs/SPECS.csv` — a machine-readable
  catalogue of every spec argument, maintained against the Census
  documentation. Filtered here to `is.save == TRUE`.
- **`christophsax/seasonal`** `R/series.R` roxygen block — the spec / long-name /
  short-name / description cross-reference.
- **X-13ARIMA-SEATS Reference Manual v1.1** (Census Bureau, April 2015),
  Chapters 2–4 read directly. Chapter 7 (per-spec documentation) and Appendix B
  (Print and Save Tables) exceeded the fetch limit and were **not** read — the
  two `seasonal` sources above cover the same ground and are what this file
  rests on.

## How `save` works (Manual §3.2, read directly)

- The **short name is the file extension.** `estimate { save = (rsd) }` writes
  `<basename>.rsd`.
- A table may be named by either its long name (`estimate.residuals`) or its
  short name (`rsd`). Both are accepted in `save`.
- `save` takes only explicit table names. The keywords `none`, `all`,
  `alltables`, `default` and `brief` are **`print`-only and invalid in `save`**.
- Saved files are tab-separated with high numeric precision and minimal
  labelling.
- Files are written to the output directory and **silently overwrite** anything
  of the same name.

## The critical naming trap

The save keyword is **not** the X-11 table number. The regARIMA component tables
are the worst case — every one of these is named for what it *is*, not for the
table it corresponds to:

| Wanted | Save keyword | File ext | X-11 table |
|---|---|---|---|
| Trading-day factors | `regression.tradingday` | `.td` | A6 |
| **Holiday factors** | `regression.holiday` | `.hol` | **A7** |
| User-regressor factors | `regression.userdef` | `.usr` | A9 |
| Combined outlier factors | `regression.outlier` | `.otl` | A8 |
| AO factors | `regression.aoutlier` | `.ao` | A8.AO |
| LS/TL/ramp factors | `regression.levelshift` | `.ls` | A8.LS |
| TC factors | `regression.temporarychange` | `.tc` | A8.TC |
| SO factors | `regression.seasonaloutlier` | `.so` | A8.SO |
| User seasonal factors | `regression.regseasonal` | `.a10` | A10 |
| Transitory factors | `regression.transitory` | `.a13` | A13 |

Writing `save = (a6 a7)` does not work. `a10` and `a13` happen to be spelled as
their table numbers; `a6`, `a7`, `a8` and `a9` are not.

## Findings that change existing plans

**`vcov` is obtainable after all.** `estimate.regcmatrix` (`.rcm`) is documented
as the *correlation* matrix when used with `print`, and the **covariance matrix
when used with `save`**. `estimate.armacmatrix` (`.acm`) is the same for the ARMA
parameters. The W.5 decision to throw from `StatsAPI.vcov` was correct *given
`.udg` alone*, but a run with `estimate { save = (rcm) }` supplies the real
matrix. See the W.7 handoff.

**Missing values are supported.** The 2015 manual's Chapter 1 says missing
values are not allowed; that statement is stale. `seasonal`'s `na.x13()` is one
line — it substitutes `NA` with **`-99999`**, X-13's default missing code — and
`series.seriesmvadj` (`.mv`) returns the series with missing values replaced by
regARIMA estimates. No `missingcode` argument is needed at the default.

**Forecasts already carry their intervals.** `forecast.forecasts` (`.fct`) is
documented as point forecasts on the original scale *along with upper and lower
prediction interval limits* — so the interval does not need assembling from
`.fvr`.

**Residual ACF/PACF are saveable tables.** `check.acf` (`.acf`), `check.pacf`
(`.pcf`) and `check.acfsquared` (`.ac2`) come with standard errors and
Ljung-Box Q-statistics per lag, direct from the binary.

---

## Full catalogue

### `series`

| Save keyword | Ext | Description |
|---|---|---|
| `series.span` | `.a1` | time series data, with associated dates (if the span argument is present, data are printed and/or saved only for the specified span) |
| `series.calendaradjorig` | `.a18` | original series adjusted for regARIMA calendar effects |
| `series.outlieradjorig` | `.a19` | original series adjusted for regARIMA outliers |
| `series.adjoriginal` | `.b1` | original series, adjusted for prior effects and forecast extended |
| `series.seriesmvadj` | `.mv` | original series with missing values replaced by regARIMA estimates |
| `series.specfile` | `.spc` | — |

### `transform`

| Save keyword | Ext | Description |
|---|---|---|
| `transform.seriesconstant` | `.a1c` | original series with value from the constant argument added to the series |
| `transform.prior` | `.a2` | prior adjustment factors, with associated dates |
| `transform.permprior` | `.a2p` | permanent prior adjustment factors, with associated dates |
| `transform.tempprior` | `.a2t` | temporary prior adjustment factors, with associated dates |
| `transform.prioradjusted` | `.a3` | prior adjusted series, with associated dates |
| `transform.permprioradjusted` | `.a3p` | prior adjusted series using only permanent prior factors, with associated dates |
| `transform.prioradjustedptd` | `.a4d` | prior adjusted series (including prior trading day adjustments), with associated dates |
| `transform.permprioradjustedptd` | `.a4p` | prior adjusted series using only permanent prior factors and prior trading day adjustments, with associated dates |
| `transform.transformed` | `.trn` | prior adjusted and transformed data, with associated dates |

### `regression`

| Save keyword | Ext | Description |
|---|---|---|
| `regression.regseasonal` | `.a10` | regARIMA user-defined seasonal factors (table A10) |
| `regression.transitory` | `.a13` | regARIMA transitory component factors from userdefined regressors (table A13) |
| `regression.aoutlier` | `.ao` | regARIMA additive (or point) outlier factors (table A8.AO) |
| `regression.holiday` | `.hol` | regARIMA holiday factors (table A7) |
| `regression.levelshift` | `.ls` | regARIMA level shift, temporary level shift and ramp outlier factors (table A8.LS) |
| `regression.outlier` | `.otl` | combined regARIMA outlier factors (table A8) |
| `regression.regressionmatrix` | `.rmx` | values of regression variables with associated dates |
| `regression.seasonaloutlier` | `.so` | regARIMA seasonal outlier factors (table A8.SO) |
| `regression.temporarychange` | `.tc` | regARIMA temporary change outlier factors (table A8.TC) |
| `regression.tradingday` | `.td` | regARIMA trading day factors (table A6) |
| `regression.userdef` | `.usr` | factors from user-defined regression variables (table A9) |

### `estimate`

| Save keyword | Ext | Description |
|---|---|---|
| `estimate.armacmatrix` | `.acm` | correlation matrix of ARMA parameter estimates if used with the print argument; covariance matrix of same if used with the save argument |
| `estimate.estimates` | `.est` | — |
| `estimate.iterations` | `.itr` | detailed output for estimation iterations, including log-likelihood values and parameters, and counts of function evaluations and iterations |
| `estimate.lkstats` | `.lks` | — |
| `estimate.model` | `.mdl` | — |
| `estimate.regcmatrix` | `.rcm` | correlation matrix of regression parameter estimates if used with the print argument; covariance matrix of same if used with the save argument |
| `estimate.regressioneffects` | `.ref` | Xb matrix of regression variables multiplied by the vector of estimated regression coefficients |
| `estimate.regressionresiduals` | `.rrs` | — |
| `estimate.residuals` | `.rsd` | model residuals with associated dates or observation numbers |
| `estimate.roots` | `.rts` | roots of the autoregressive and moving average operators in the estimated model |

### `check`

| Save keyword | Ext | Description |
|---|---|---|
| `check.acfsquared` | `.ac2` | autocorrelation function of squared residuals with standard errors and Ljung-Box Q-statistics computed through each lag |
| `check.acf` | `.acf` | autocorrelation function of residuals with standard errors and Ljung-Box Q-statistics computed through each lag |
| `check.pacf` | `.pcf` | partial autocorrelation function of residuals with standard errors |

### `forecast`

| Save keyword | Ext | Description |
|---|---|---|
| `forecast.backcasts` | `.bct` | point backcasts on the original scale, along with upper and lower prediction interval limits |
| `forecast.transformedbcst` | `.btr` | backcasts on the transformed scale, with corresponding forecast standard errors |
| `forecast.forecasts` | `.fct` | point forecasts on the original scale, along with upper and lower prediction interval limits |
| `forecast.transformed` | `.ftr` | forecasts on the transformed scale, with corresponding forecast standard errors |
| `forecast.variances` | `.fvr` | forecast error variances on the transformed scale, showing the contributions of the error assuming the model is completely known (stochastic varian... |

### `outlier`

| Save keyword | Ext | Description |
|---|---|---|
| `outlier.finaltests` | `.fts` | t-statistics for every time point and outlier type generated during the final outlier detection iteration (not saved when automdl/pickmdl is used) |
| `outlier.iterations` | `.oit` | detailed results for each iteration of outlier detection including outliers detected, outliers deleted, model parameter estimates, and robust and n... |

### `identify`

| Save keyword | Ext | Description |
|---|---|---|
| `identify.acf` | `.iac` | sample autocorrelation function(s), with standard errors and Ljung-Box Q-statistics for each lag |
| `identify.pacf` | `.ipc` | sample partial autocorrelation function(s) with standard errors for each lag |

### `x11`

| Save keyword | Ext | Description |
|---|---|---|
| `x11.seasonaladjregsea` | `.ars` | seasonal factors adjusted for user-defined seasonal regARIMA component |
| `x11.seasonalb10` | `.b10` | seasonal factors, B iteration |
| `x11.seasadjb11` | `.b11` | seasonally adjusted series, B iteration |
| `x11.irregularb` | `.b13` | irregular component, B iteration |
| `x11.irrwtb` | `.b17` | preliminary weights for the irregular component |
| `x11.tdadjorigb` | `.b19` | original series adjusted for preliminary trading day |
| `x11.trendb2` | `.b2` | preliminary trend-cycle, B iteration |
| `x11.extremeb` | `.b20` | extreme values, B iteration |
| `x11.sib3` | `.b3` | preliminary unmodified SI-ratios (differences) |
| `x11.seasonalb5` | `.b5` | preliminary seasonal factors, B iteration |
| `x11.seasadjb6` | `.b6` | preliminary seasonally adjusted series, B iteration |
| `x11.trendb7` | `.b7` | preliminary trend-cycle, B iteration |
| `x11.sib8` | `.b8` | unmodified SI-ratios (differences) |
| `x11.biasfactor` | `.bcf` | bias correction factors |
| `x11.adjoriginalc` | `.c1` | original series modified for outliers, trading day and prior factors, C iteration |
| `x11.seasonalc10` | `.c10` | preliminary seasonal factors, C iteration |
| `x11.seasadjc11` | `.c11` | seasonally adjusted series, C iteration |
| `x11.irregularc` | `.c13` | irregular component, C iteration |
| `x11.irrwt` | `.c17` | final weights for the irregular component |
| `x11.tdadjorig` | `.c19` | original series adjusted for final trading day |
| `x11.trendc2` | `.c2` | preliminary trend-cycle, C iteration |
| `x11.extreme` | `.c20` | extreme values, C iteration |
| `x11.modsic4` | `.c4` | modified SI-ratios (differences), C iteration |
| `x11.seasonalc5` | `.c5` | preliminary seasonal factors, C iteration |
| `x11.seasadjc6` | `.c6` | preliminary seasonally adjusted series, C iteration |
| `x11.trendc7` | `.c7` | preliminary trend-cycle, C iteration |
| `x11.replacsic9` | `.c9` | modified SI-ratios (differences), C iteration |
| `x11.combholiday` | `.chl` | combined holiday prior adjustment factors, A16 table |
| `x11.adjoriginald` | `.d1` | original series modified for outliers, trading day and prior factors, D iteration |
| `x11.seasonal` | `.d10` | final seasonal factors |
| `x11.seasadj` | `.d11` | final seasonally adjusted series |
| `x11.trend` | `.d12` | final trend-cycle |
| `x11.irregular` | `.d13` | final irregular component |
| `x11.adjustfac` | `.d16` | combined seasonal and trading day factors |
| `x11.calendar` | `.d18` | combined holiday and trading day factors |
| `x11.trendd2` | `.d2` | preliminary trend-cycle, D iteration |
| `x11.modsid4` | `.d4` | modified SI-ratios (differences), D iteration |
| `x11.seasonald5` | `.d5` | preliminary seasonal factors, D iteration |
| `x11.seasadjd6` | `.d6` | preliminary seasonally adjusted series, D iteration |
| `x11.trendd7` | `.d7` | preliminary trend-cycle, D iteration |
| `x11.unmodsi` | `.d8` | final unmodified SI-ratios (differences) |
| `x11.unmodsiox` | `.d8b` | final unmodified SI-ratios, with labels for outliers and extreme values |
| `x11.replacsi` | `.d9` | final replacement values for extreme SI-ratios (differences), D iteration |
| `x11.modoriginal` | `.e1` | original series modified for zero-weighted extreme values |
| `x11.robustsa` | `.e11` | robust final seasonally adjusted series |
| `x11.adjustmentratio` | `.e18` | final adjustment ratios (original series/seasonally adjusted series) |
| `x11.modseasadj` | `.e2` | seasonally adjusted series modified for zero-weighted extreme values |
| `x11.modirregular` | `.e3` | irregular component modified for zero-weighted extreme values |
| `x11.yrtotals` | `.e4` | ratio of yearly totals of original and seasonally adjusted series |
| `x11.origchanges` | `.e5` | percent changes (differences) in original series |
| `x11.sachanges` | `.e6` | percent changes (differences) in seasonally adjusted series |
| `x11.trendchanges` | `.e7` | percent changes (differences) in final trend component series |
| `x11.calendaradjchanges` | `.e8` | percent changes (differences) in original series adjusted for calendar effects |
| `x11.mcdmovavg` | `.f1` | MCD moving average of the final seasonally adjusted series |
| `x11.adjustdiff` | `.fad` | final adjustment difference (only for pseudo-additive seasonal adjustment) |
| `x11.seasonaldiff` | `.fsd` | final seasonal difference (only for pseudo-additive seasonal adjustment) |
| `x11.irregularadjao` | `.ira` | final irregular component adjusted for point outliers |
| `x11.adjustfacpct` | `.paf` | combined adjustment factors, expressed as percentages if appropriate |
| `x11.origchangespct` | `.pe5` | percent changes in the original series |
| `x11.sachangespct` | `.pe6` | percent changes in seasonally adjusted series |
| `x11.trendchangespct` | `.pe7` | percent changes in final trend cycle |
| `x11.calendaradjchangespct` | `.pe8` | percent changes in original series adjusted for calendar factors |
| `x11.irregularpct` | `.pir` | final irregular component, expressed as percentages if appropriate |
| `x11.seasonalpct` | `.psf` | final seasonal factors, expressed as percentages if appropriate |
| `x11.seasadjconst` | `.sac` | final seasonally adjusted series with constant from transform spec included |
| `x11.trendconst` | `.tac` | final trend component with constant from transform spec included |
| `x11.totaladjustment` | `.tad` | total adjustment factors (only printed out if the original series contains values that are <= 0) |
| `x11.trendadjls` | `.tal` | final trend-cycle adjusted for level shift outliers |

### `x11regression`

| Save keyword | Ext | Description |
|---|---|---|
| `x11regression.priortd` | `.a4` | prior trading day weights and factors |
| `x11regression.extremevalb` | `.b14` | irregulars excluded from the irregular regression, B iteration |
| `x11regression.x11regb` | `.b15` | preliminary irregular regression coefficients and diagnostics |
| `x11regression.tradingdayb` | `.b16` | preliminary trading day factors and weights |
| `x11regression.combtradingdayb` | `.b18` | preliminary trading day factors from combined daily weights |
| `x11regression.combcalendarb` | `.bcc` | preliminary calendar factors from combined daily weights |
| `x11regression.calendarb` | `.bxc` | preliminary calendar factors |
| `x11regression.holidayb` | `.bxh` | preliminary holiday factors |
| `x11regression.extremeval` | `.c14` | irregulars excluded from the irregular regression, C iteration |
| `x11regression.x11reg` | `.c15` | final irregular regression coefficients and diagnostics |
| `x11regression.tradingday` | `.c16` | final trading day factors and weights |
| `x11regression.combtradingday` | `.c18` | final trading day factors from combined daily weights |
| `x11regression.calendar` | `.xca` | final calendar factors (trading day and holiday) |
| `x11regression.combcalendar` | `.xcc` | final calendar factors from combined daily weights |
| `x11regression.holiday` | `.xhl` | final holiday factors |
| `x11regression.outlieriter` | `.xoi` | detailed results for each iteration of outlier detection including outliers detected, outliers deleted, model parameter estimates, and robust and n... |
| `x11regression.xregressioncmatrix` | `.xrc` | correlation matrix of irregular regression parameter estimates if used with the print argument; covariance matrix of same if used with the save arg... |
| `x11regression.xregressionmatrix` | `.xrm` | values of irregular regression variables with associated dates |

### `seats`

| Save keyword | Ext | Description |
|---|---|---|
| `seats.seasonaladjfcstdecomp` | `.afd` | forecast of the final SEATS seasonal adjustment |
| `seats.seasonaladjse` | `.ase` | standard error of final seasonally adjusted series |
| `seats.transitoryse` | `.cse` | standard error of final transitory component |
| `seats.cycle` | `.cyc` | cycle component |
| `seats.difforiginal` | `.dor` | fully differenced transformed original series |
| `seats.diffseasonaladj` | `.dsa` | fully differenced transformed SEATS seasonal adjustment |
| `seats.difftrend` | `.dtr` | fully differenced transformed SEATS trend |
| `seats.filtersaconc` | `.fac` | concurrent finite seasonal adjustment filter |
| `seats.filtersasym` | `.faf` | symmetric finite seasonal adjustment filter |
| `seats.filtertrendconc` | `.ftc` | concurrent finite trend filter |
| `seats.filtertrendsym` | `.ftf` | symmetric finite trend filter |
| `seats.squaredgainsaconc` | `.gac` | squared gain for finite concurrent seasonal adjustment filter |
| `seats.squaredgainsasym` | `.gaf` | squared gain for finite symmetric seasonal adjustment filter |
| `seats.squaredgaintrendconc` | `.gtc` | squared gain for finite concurrent trend filter |
| `seats.squaredgaintrendsym` | `.gtf` | squared gain for finite symmetric trend filter |
| `seats.longtermtrend` | `.ltt` | long term trend |
| `seats.componentmodels` | `.mdc` | models for the components |
| `seats.seriesfcstdecomp` | `.ofd` | forecast of the series component |
| `seats.pseudoinnovsadj` | `.pia` | pseudo-innovations of the final SEATS seasonal adjustment |
| `seats.pseudoinnovtrend` | `.pic` | pseudo-innovations of the trend component |
| `seats.pseudoinnovseasonal` | `.pis` | pseudo-innovations of the seasonal component |
| `seats.pseudoinnovtransitory` | `.pit` | pseudo-innovations of the transitory component |
| `seats.adjustfacpct` | `.psa` | combined adjustment factors, expressed as percentages if appropriate |
| `seats.transitorypct` | `.psc` | final transitory component, expressed as percentages if appropriate |
| `seats.irregularpct` | `.psi` | final irregular component, expressed as percentages if appropriate |
| `seats.seasonalpct` | `.pss` | final seasonal factors, expressed as percentages if appropriate |
| `seats.seasonal` | `.s10` | final SEATS seasonal component |
| `seats.seasonaladj` | `.s11` | final SEATS seasonal adjustment |
| `seats.trend` | `.s12` | final SEATS trend component |
| `seats.irregular` | `.s13` | final SEATS irregular component |
| `seats.transitory` | `.s14` | final SEATS transitory component |
| `seats.adjustfac` | `.s16` | final SEATS combined adjustment factors |
| `seats.adjustmentratio` | `.s18` | final SEATS adjustment ratio |
| `seats.seasonaladjoutlieradj` | `.se2` | final SEATS seasonal adjustment, outlier adjusted |
| `seats.irregularoutlieradj` | `.se3` | final SEATS irregular component, outlier adjusted |
| `seats.seasadjconst` | `.sec` | final SEATS seasonal adjustment with constant term included |
| `seats.seasonalfcstdecomp` | `.sfd` | forecast of the seasonal component |
| `seats.seasonalse` | `.sse` | standard error of final steasonal component |
| `seats.seasonalsum` | `.ssm` | seasonal-period-length sums of final SEATS seasonal component |
| `seats.totaladjustment` | `.sta` | total adjustment factors for SEATS seasonal adjustment |
| `seats.trendconst` | `.stc` | final SEATS trend component with constant term included |
| `seats.trendadjls` | `.stl` | level shift adjusted trend |
| `seats.timeshiftsaconc` | `.tac` | final trend component with constant from transform spec included |
| `seats.trendfcstdecomp` | `.tfd` | forecast of the trend component |
| `seats.trendse` | `.tse` | standard error of final trend component |
| `seats.timeshifttrendconc` | `.ttc` | time shift for finite concurrent trend filter |
| `seats.wkendfilter` | `.wkf` | end filters of the semi-infinite Wiener-Kolmogorov filter |
| `seats.transitoryfcstdecomp` | `.yfd` | forecast of the transitory component |

### `force`

| Save keyword | Ext | Description |
|---|---|---|
| `force.revsachanges` | `.e6a` | percent changes (differences) in seasonally adjusted series with revised yearly totals |
| `force.rndsachanges` | `.e6r` | percent changes (differences) in rounded seasonally adjusted series |
| `force.forcefactor` | `.ffc` | factors applied to get seasonally adjusted series with constrained yearly totals (if type = regress or type = denton) |
| `force.revsachangespct` | `.p6a` | percent changes in seasonally adjusted series with forced yearly totals |
| `force.rndsachangespct` | `.p6r` | percent changes in rounded seasonally adjusted series |
| `force.saround` | `.rnd` | rounded final seasonally adjusted series (if round = yes) or the rounded final seasonally adjusted series with constrained yearly totals (if type =... |
| `force.seasadjtot` | `.saa` | final seasonally adjusted series with constrained yearly totals (if type = regress or type = denton) |

### `slidingspans`

| Save keyword | Ext | Description |
|---|---|---|
| `slidingspans.saspans` | `.ads` | — |
| `slidingspans.indsaspans` | `.ais` | indirect seasonally adjusted series from all sliding spans |
| `slidingspans.chngspans` | `.chs` | month-to-month (or quarter-to-quarter) changes from all sliding spans |
| `slidingspans.indchngspans` | `.cis` | indirect month-to-month (or quarter-to-quarter) changes from all sliding spans |
| `slidingspans.sfspans` | `.sfs` | seasonal factors from all sliding spans |
| `slidingspans.indsfspans` | `.sis` | indirect seasonal factors from all sliding spans |
| `slidingspans.tdspans` | `.tds` | trading day factors from all sliding spans |
| `slidingspans.ychngspans` | `.ycs` | year-to-year changes from all sliding spans |
| `slidingspans.indychngspans` | `.yis` | indirect year-to-year changes from all sliding spans |

### `history`

| Save keyword | Ext | Description |
|---|---|---|
| `history.armahistory` | `.amh` | history of estimated AR and MA coefficients from the regARIMA model |
| `history.chngestimates` | `.che` | concurrent and most recent estimate of the month-tomonth (or quarter-to-quarter) changes in the seasonally adjusted data |
| `history.chngrevisions` | `.chr` | revision from concurrent to most recent estimate of the month-to-month (or quarter-to-quarter) changes in the seasonally adjusted data |
| `history.fcsterrors` | `.fce` | revision history of the accumulated sum of squared forecast errors |
| `history.fcsthistory` | `.fch` | listing of the forecast and forecast errors used to generate accumulated sum of squared forecast errors |
| `history.indsaestimates` | `.iae` | concurrent and most recent estimate of the indirect seasonally adjusted data |
| `history.indsarevisions` | `.iar` | revision from concurrent to most recent estimate of the indirect seasonally adjusted series |
| `history.lkhdhistory` | `.lkh` | history of AICC and likelihood values |
| `history.outlierhistory` | `.rot` | record of outliers removed and kept for the revisions history (printed only if automatic outlier identification is used) |
| `history.saestimates` | `.sae` | concurrent and most recent estimate of the seasonally adjusted data |
| `history.sarevisions` | `.sar` | revision from concurrent to most recent estimate of the seasonally adjusted data |
| `history.sfestimates` | `.sfe` | concurrent and most recent estimate of the seasonal factors and projected seasonal factors |
| `history.sfilterhistory` | `.sfh` | record of seasonal filter selection for each observation in the revisions history (printed only if automatic seasonal filter selection is used) |
| `history.sfrevisions` | `.sfr` | revision from concurrent to most recent estimate of the seasonal factor, as well as projected seasonal factors |
| `history.seatsmdlhistory` | `.smh` | SEATS ARIMA model history |
| `history.trendchngestimates` | `.tce` | concurrent and most recent estimate of the month-tomonth (or quarter-to-quarter) changes in the trend component |
| `history.trendchngrevisions` | `.tcr` | revision from concurrent to most recent estimate of the month-to-month (or quarter-to-quarter) changes in the trend component |
| `history.tdhistory` | `.tdh` | history of estimated trading day regression coefficients from the regARIMA model |
| `history.trendestimates` | `.tre` | concurrent and most recent estimate of the trend component |
| `history.trendrevisions` | `.trr` | revision from concurrent to most recent estimate of the trend component |

### `spectrum`

| Save keyword | Ext | Description |
|---|---|---|
| `spectrum.speccomposite` | `.is0` | spectral plot of first-differenced aggregate series |
| `spectrum.specindsa` | `.is1` | spectral plot of the first-differenced indirect seasonally adjusted series |
| `spectrum.specindirr` | `.is2` | spectral plot of outlier-modified irregular series from the indirect seasonal adjustment |
| `spectrum.spectukeycomposite` | `.it0` | Tukey spectrum of the first-differenced aggregate series |
| `spectrum.spectukeyindsa` | `.it1` | Tukey spectrum of the first-differenced indirect seasonally adjusted series |
| `spectrum.spectukeyindirr` | `.it2` | Tukey spectrum of the outlier-modified irregular series from the indirect seasonal adjustment |
| `spectrum.specseatssa` | `.s1s` | spectrum of the differenced final SEATS seasonal adjustment |
| `spectrum.specseatsirr` | `.s2s` | spectrum of the final SEATS irregular |
| `spectrum.specextresiduals` | `.ser` | spectrum of the extended residuals |
| `spectrum.specorig` | `.sp0` | spectral plot of the first-differenced original series |
| `spectrum.specsa` | `.sp1` | spectral plot of differenced, X-11 seasonally adjusted series (or of the logged seasonally adjusted series if mode = logadd or mode = mult) |
| `spectrum.specirr` | `.sp2` | spectral plot of outlier-modified X-11 irregular series |
| `spectrum.specresidual` | `.spr` | spectral plot of the regARIMA model residuals |
| `spectrum.spectukeyorig` | `.st0` | Tukey spectrum of the first-differenced original series |
| `spectrum.spectukeysa` | `.st1` | Tukey spectrum of the differenced, X-11 seasonally adjusted series (or of the logged seasonally adjusted series if mode = logadd or mode = mult) |
| `spectrum.spectukeyirr` | `.st2` | Tukey spectrum of the outlier-modified X-11 irregular series |
| `spectrum.spectukeyresidual` | `.str` | Tukey spectrum of the regARIMA model residuals |
| `spectrum.spectukeyseatssa` | `.t1s` | Tukey spectrum of the differenced final SEATS seasonal adjustment |
| `spectrum.spectukeyseatsirr` | `.t2s` | Tukey spectrum of the final SEATS irregular |
| `spectrum.spectukeyextresiduals` | `.ter` | Tukey spectrum of the extended residuals |

### `composite`

| Save keyword | Ext | Description |
|---|---|---|
| `composite.adjcompositesrs` | `.b1` | original series, adjusted for prior effects and forecast extended |
| `composite.adjcompositeplot` | `.b1p` | — |
| `composite.adjcompositesrsplot` | `.b1p` | — |
| `composite.calendaradjcomposite` | `.cac` | aggregated time series data, adjusted for regARIMA calendar effects. |
| `composite.compositesrs` | `.cms` | aggregated time series data, with associated dates |
| `composite.indadjustmentratio` | `.i18` | — |
| `composite.indrevsachanges` | `.i6a` | percent changes for indirect seasonally adjusted series with revised yearly totals |
| `composite.indrndsachanges` | `.i6r` | percent changes (differences) in the rounded indirect seasonally adjusted series |
| `composite.prioradjcomposite` | `.ia3` | composite series adjusted for user-defined prior adjustments applied at the component level |
| `composite.indadjsatot` | `.iaa` | final indirect seasonally adjusted series, with yearly totals adjusted to match the original series |
| `composite.indadjustfac` | `.iaf` | final combined adjustment factors for the indirect seasonal adjustment |
| `composite.indaoutlier` | `.iao` | final indirect AO outliers |
| `composite.indcalendar` | `.ica` | final calendar factors for the indirect seasonal adjustment |
| `composite.indunmodsi` | `.id8` | final unmodified SI-ratios (differences) for the indirect adjustment |
| `composite.indreplacsi` | `.id9` | final replacement values for extreme SI-ratios (differences) for the indirect adjustment |
| `composite.indmodoriginal` | `.ie1` | original series modified for extreme values from the indirect seasonal adjustment |
| `composite.indmodsadj` | `.ie2` | seasonally adjusted series modified for extreme values from the indirect seasonal adjustment |
| `composite.indmodirr` | `.ie3` | irregular component modified for extreme values from the indirect seasonal adjustment |
| `composite.origchanges` | `.ie5` | percent changes (differences) in the original series |
| `composite.indsachanges` | `.ie6` | percent changes (differences) in the indirect seasonally adjusted series |
| `composite.indtrendchanges` | `.ie7` | percent changes (differences) in the indirect final trend component |
| `composite.indcalendaradjchanges` | `.ie8` | — |
| `composite.indrobustsa` | `.iee` | final indirect seasonally adjusted series modified for extreme values |
| `composite.indmcdmovavg` | `.if1` | MCD moving average of the final indirect seasonally adjusted series |
| `composite.indforcefactor` | `.iff` | — |
| `composite.indirregular` | `.iir` | final irregular component for the indirect adjustment |
| `composite.indlevelshift` | `.ils` | final indirect LS outliers |
| `composite.origchangespct` | `.ip5` | — |
| `composite.indsachangespct` | `.ip6` | — |
| `composite.indtrendchangespct` | `.ip7` | — |
| `composite.indcalendaradjchangespct` | `.ip8` | — |
| `composite.indrevsachangespct` | `.ipa` | — |
| `composite.indadjustfacpct` | `.ipf` | — |
| `composite.indirregularpct` | `.ipi` | — |
| `composite.indrndsachangespct` | `.ipr` | — |
| `composite.indseasonalpct` | `.ips` | — |
| `composite.indsadjround` | `.irn` | rounded indirect seasonally adjusted series |
| `composite.indseasadj` | `.isa` | final indirect seasonally adjusted series |
| `composite.indseasonaldiff` | `.isd` | final seasonal difference for the indirect seasonal adjustment (only for pseudo-additive seasonal adjustment) |
| `composite.indseasonal` | `.isf` | final seasonal factors for the indirect seasonal adjustment |
| `composite.indtotaladjustment` | `.ita` | total indirect adjustment factors (only produced if the original series contains values that are <= 0) |
| `composite.indtrend` | `.itn` | final trend-cycle for the indirect adjustment |
| `composite.outlieradjcomposite` | `.oac` | aggregated time series data, adjusted for outliers. |


---

**281 saveable tables** across 16 specs.
