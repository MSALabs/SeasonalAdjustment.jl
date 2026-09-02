# B. Further Reading

No prose beyond what each entry needs. Every date and attribution
below was checked directly against a primary or near-primary source
while writing this book, not restated from memory — see Chapter 3's
own note on the one popular claim that could not be verified this way
and was therefore left out.

## The original method

Shiskin, J., Young, A. H., and Musgrave, J. C. (1967). *The X-11 Variant
of the Census Method II Seasonal Adjustment Program.* Technical Paper
No. 15, U.S. Bureau of the Census. The program itself dates to 1965;
the technical paper describing it was published in 1967.

Ladiray, D. and Quenneville, B. (2001). *Seasonal Adjustment with the
X-11 Method.* Springer Lecture Notes in Statistics 158. The book on
X-11 itself, table by table — it predates X-12, and so covers neither
regARIMA nor SEATS, but nothing else explains the filtering at this
resolution. The primary source for Part II of this book.

## Forecast extension

Dagum, E. B. (1980). *The X-11-ARIMA Seasonal Adjustment Method.*
Statistics Canada. The paper that added forecast extension ahead of
X-11's asymmetric end filters — the subject of Chapter 9. A revised
version, X11ARIMA/88, followed in 1988.

## regARIMA and the modern diagnostic battery

Findley, D. F., Monsell, B. C., Bell, W. R., Otto, M. C., and Chen,
B.-C. (1998). "New Capabilities and Methods of the X-12-ARIMA
Seasonal-Adjustment Program." *Journal of Business & Economic
Statistics*, 16(2), 127–152. The design paper for regARIMA, automatic
outlier detection, and most of what Part III and Part V of this book
cover.

## SEATS and model-based decomposition

Gómez, V. and Maravall, A. (1996). *Programs TRAMO and SEATS:
Instructions for the User.* Banco de España. The origin of the SEATS
engine X-13ARIMA-SEATS incorporates.

Dagum, E. B. and Bianconcini, S. (2016). *Seasonal Adjustment Methods
and Real Time Trend-Cycle Estimation.* Springer. The modern treatment
and standard reference for SEATS — the primary source for Part IV of
this book, beyond what could be verified by running the binary
directly.

## The current program

U.S. Census Bureau. *X-13ARIMA-SEATS Reference Manual*, Version 1.1
(April 2015). The authoritative source on every specification and
every option; Chapter 7 is the per-spec reference, Appendix B lists
the output tables. X-13ARIMA-SEATS itself was first released in July
2012.

## Practice, not algorithm

Eurostat. *ESS Guidelines on Seasonal Adjustment.* Freely available,
and concerned with practice rather than method: when to force annual
totals, how often to re-identify models, what revision policy to
publish. Referenced throughout this book's "In official statistics"
boxes.
