```@meta
CurrentModule = SeasonalAdjustment
```

# Reproducibility and Production

One paragraph: automatic selection is convenient during exploration and
a liability once you publish. This page is about freezing a
specification, and what "frozen" does and does not guarantee.

## How do I freeze an automatic model?

```julia
res = x13(dataset("airline"); automdl = true, outlier = true, transform = :auto)
frozen = static(res)
```

[`static`](@ref) resolves every automatic decision — the ARIMA order,
the transform, any auto-detected outliers — into an explicit
`X13Spec`. Run that specification from then on and the model stops
moving underneath you as new data arrives.

## Why is a frozen spec not bit-identical?

```julia
res2 = x13(frozen)
res.seasonally_adjusted ≈ res2.seasonally_adjusted   # true
res.seasonally_adjusted == res2.seasonally_adjusted  # not guaranteed
```

Re-running a frozen specification reproduces the original to about six
significant figures, not exactly, because estimation converges
slightly differently when a model is *given* rather than *searched
for* — the numerical optimisation path differs even though the model
and data are identical. Compare with `isapprox`, never `==`.

## What should I store with published figures?

Three things, so a figure can actually be reproduced later:

- **The frozen `X13Spec`** — `static(res)`, or at minimum the exact
  keyword arguments passed to `x13()`.
- **The package version** — `Pkg.status("SeasonalAdjustment")`, since
  parsing or diagnostic behaviour could change between releases.
- **The binary version** — the `x13prebuilt` artifact revision this
  package pins (`Artifacts.toml`), since X-13 itself is the actual
  computation.

None of this is enforced by the package; it is a discipline the same
way `static()` itself is one.

## How often should I re-identify?

This is policy, not package behaviour, and the package deliberately
does not have an opinion baked in. Two common conventions:

**Concurrent adjustment** re-estimates the entire specification every
period — most current model, but the published series keeps revising.
**Forward-factor adjustment** freezes the specification for a fixed
period (often a year) and only applies it, trading some accuracy for a
published number that does not move again until the next
re-identification.

Eurostat's ESS Guidelines on Seasonal Adjustment discuss this tradeoff
directly and are the reference worth reading before setting an
organisational policy — see the
[End-of-Series Problem](../introduction/09-end-of-series.md) chapter of
the *Introduction* for the argument in full, with real revision
numbers.

---

**See also:** [Introduction chapter 9](../introduction/09-end-of-series.md)
for why revision happens at all, measured directly rather than assumed.
[`static`](@ref) in the [API Reference](../api.md).
