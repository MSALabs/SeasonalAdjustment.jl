# 16. Why So Many Diagnostics?

Regression gets by with a handful of checks — a few residual plots,
maybe a Ljung-Box test, an R². Seasonal adjustment has dozens: eleven M
statistics, a Q and a Q2, QS tests, stable and moving seasonality F-tests,
spectral peak flags, Ljung-Box, normality tests, sliding spans, revision
histories. Why so many, for what looks like the same basic task?

Chapter 2 gave the answer before this chapter needed to argue for it:
**the decomposition is not identified.** Infinitely many trend-and-seasonal
splits reproduce the same observed series exactly, and there is no true
seasonal component sitting behind the data to compare an estimate
against. A regression has a likelihood, and a likelihood ratio test can
ask "is this model right, relative to that one." Seasonal adjustment has
no equivalent question to ask, because there is no single right answer
for any test to be a test *of*.

What the field built instead is an empirical substitute: a battery of
checks, each targeting one specific way an adjustment can go wrong, none
of them individually a certificate of correctness. Four families organise
the chapters that follow:

| Question | Diagnostics | Chapter |
|---|---|---|
| Is the output plausible? | M1–M11, Q | 17 |
| Did it actually remove the seasonality? | QS, F-tests, spectrum | 18 |
| Is the model behind it sound? | Ljung-Box, normality, residual ACF | 19 |
| Will it still look like this next month? | sliding spans, revision history | 20 |

None of these is a certificate, and — this is the point the next three
chapters demonstrate rather than merely assert — **they can disagree with
each other.** That is not a malfunction. Each one measures something
genuinely different, so there is no reason to expect them to always agree,
and treating an isolated pass or an isolated fail as decisive is a
misreading of what any single diagnostic can tell you on its own.

The clearest illustration of exactly this did not need to be constructed.
It is the canonical airline series, adjusted with ordinary, sensible
settings: it passes every headline check in Chapter 17, and Chapter 18
shows the very same adjustment's spectrum disagreeing with its own QS
test about whether the seasonality is really gone. Chapter 19 then finds
autocorrelated residuals in a model that, by every measure in Chapter 17,
looked entirely adequate. None of this makes the adjustment bad. It makes
the point of this chapter directly, on the most-used series in the field,
under defaults nobody would call unusual.

---

**See also:** Chapter 2 for where the non-identification argument this
chapter depends on was first made. Appendix A for the operational,
no-prose form of the taxonomy above.
