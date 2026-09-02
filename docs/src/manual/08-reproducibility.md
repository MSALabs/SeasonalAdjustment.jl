```@meta
CurrentModule = SeasonalAdjustment
```

# Reproducibility and Production

One paragraph: automatic selection is convenient while exploring and a
liability once figures are published. This page concerns freezing a
specification, and what "frozen" does and does not guarantee.

## How do I freeze an automatic model?

```julia
res = x13(dataset("airline"); automdl = true, outlier = true, transform = :auto)
frozen = static(res)
```

[`static`](@ref) resolves every automatic decision — the ARIMA order,
the transform, any auto-detected outliers — into an explicit
`X13Spec`. Running that specification from then on stops the model
moving underneath one as new data arrives.

## Why is a frozen spec not bit-identical?

```julia
res2 = x13(frozen)
res.seasonally_adjusted ≈ res2.seasonally_adjusted   # true
res.seasonally_adjusted == res2.seasonally_adjusted  # not guaranteed
```

Re-running a frozen specification reproduces the original to about six
significant figures, not exactly, estimation converging slightly
differently when a model is *given* rather than *searched for* — the
numerical optimisation path differs even where the model and data are
themselves identical. Compare with `isapprox`, never `==`.

## What should I store with published figures?

Three things, so that a figure may actually be reproduced later:

- **The frozen `X13Spec`** — `static(res)`, or at the very least the
  exact keyword arguments passed to `x13()`.
- **The package version** — `Pkg.status("SeasonalAdjustment")`,
  parsing or diagnostic behaviour being liable to change between
  releases.
- **The binary version** — the `x13prebuilt` artifact revision this
  package pins (`Artifacts.toml`), X-13 itself being the actual
  computation underneath.

None of this is enforced by the package; it is a discipline in the
same way `static()` itself is one.

## How often should I re-identify?

This is a matter of policy, not package behaviour, and the package
deliberately holds no opinion of its own baked in. Two common
conventions exist:

**Concurrent adjustment** re-estimates the entire specification every
period — the most current model available, though the published
series keeps on revising as a result. **Forward-factor adjustment**
freezes the specification for a fixed period (often a year) and only
applies it thereafter, trading some accuracy away for a published
number that does not move again until the next re-identification.

Eurostat's ESS Guidelines on Seasonal Adjustment discuss this
trade-off directly, and are the reference worth reading before
settling on an organisational policy — see the
[End-of-Series Problem](../introduction/09-end-of-series.md) chapter
of the *Introduction* for the argument in full, with real revision
numbers to accompany it.

---

**See also:** [Introduction chapter 9](../introduction/09-end-of-series.md)
for why revision happens at all, measured directly rather than merely
assumed. [`static`](@ref) in the [API Reference](../api.md).
