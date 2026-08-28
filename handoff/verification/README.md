# Real ground truth, generated directly from the actual x13prebuilt binary

Not synthetic examples -- both of these were produced by actually
running x13prebuilt (v1.1.57, linux/64) during this package's design
phase, pinned to commit 61c4043949f43c1ea5ad0fbbc7b6c11fc5073d19.

## airline_baseline/
The Box-Jenkins airline passengers series (1949-1960), plain X-11,
no custom regressors. Real D10/D11/D12/D13 tables, 144 months each.
Use this as the primary W.1-W.4 regression fixture.

## diwali_regressor_proof/
The identical series, but with a synthetic Diwali-effect user-defined
regressor added to the regression spec. Compare its D10 against
airline_baseline/airline_official.d10 directly -- October's seasonal factor
shifts from 0.898593816033472 to 0.753973303751993 (1949), proving the
custom regressor was genuinely absorbed into the RegARIMA fit, not
silently ignored. This is the reference case for W.0's whole purpose.
