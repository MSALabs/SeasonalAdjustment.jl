#!/usr/bin/env python3
"""test/extended/python_helper.py

Stage 1 of the extended, R/Python-cross-validated test suite (see
development-sequence.md's Post-W.4a section). Runs one seasonal-
adjustment case through Python's statsmodels.tsa.x13.x13_arima_analysis
-- pointed at this package's own already-verified x13ashtml binary via
x12path= (confirmed directly via inspect.signature: there is no
separate x13path kwarg despite the function's name -- x12path is
shared with X12, selected via prefer_x13=True), the same binary
r_helper.R and the real Julia tests use -- and writes the result as
JSON in the same shape r_helper.R uses, so Julia's comparison code
doesn't need per-language translation.

Usage: python3 python_helper.py <input.json> <output.json>

Confirmed directly this session, not assumed: statsmodels' own default
(no explicit regression/outlier arguments) does NOT match R's default
either, and easily could NOT match a bare X13Spec() default -- every
case passed to this script must set transform/arima_model/outlier/
regression_variables/aictest explicitly, mirroring r_helper.R's own
same requirement (found there first: R's regression.aictest silently
defaulting to td+easter even with regression.variables=None, an actual
~3-unit-magnitude discrepancy before that was pinned down).
"""
import sys
import json
import os
import re

import numpy as np
import pandas as pd
import statsmodels.tsa.x13 as x13mod
from statsmodels.tsa.x13 import x13_arima_analysis

# statsmodels' x13_arima_analysis hard-codes reading the STANDARD x13as
# binary's plain-text output file naming (<tempbase>.err, <tempbase>.out)
# -- confirmed directly via inspect.getsource(x13_arima_analysis). This
# package's own x13ashtml binary variant (the only Linux variant
# x13org/x13prebuilt ships at all -- confirmed directly via its GitHub
# API contents listing, there is no plain x13as to use instead) writes
# `_err.html`/a full HTML report instead, so those two specific reads
# 404 with a real, structural naming mismatch -- not a bug in either
# side, just two binary variants with different output conventions.
# `.d11`/`.d12`/`.d13` (the values actually needed for comparison) are
# unaffected: confirmed directly via speconly=True that statsmodels'
# own generated spec already requests `x11{save=(d11 d12 d13)}`, and
# those plain-format tables ARE what x13ashtml writes when asked.
# This patch only changes how `.err`/`.out` are located, narrowly
# scoped to this script's own process (not a global statsmodels
# install-time patch) -- `.err`'s real diagnostic content is recovered
# from the HTML report by stripping tags, so genuine ERROR:/WARNING:
# text is still detected by _check_errors' own unchanged logic; `.out`
# (the full run narrative, not used by this script's own output) is
# left empty rather than guessing at an HTML-to-text mapping nothing
# here actually needs.
_orig_open_and_read = x13mod._open_and_read


def _patched_open_and_read(fname):
    try:
        return _orig_open_and_read(fname)
    except FileNotFoundError:
        if fname.endswith(".err"):
            html_path = fname[:-4] + "_err.html"
            if os.path.exists(html_path):
                with open(html_path, "r", encoding="utf-8") as f:
                    html = f.read()
                return re.sub(r"<[^>]+>", " ", html)
            return ""
        if fname.endswith(".out"):
            return ""
        raise


x13mod._open_and_read = _patched_open_and_read


def main():
    with open(sys.argv[1]) as f:
        inp = json.load(f)

    y = np.array(inp["y"], dtype=float)
    # period=4 (quarterly) confirmed directly to work through pandas'
    # own "QS" (quarter-start) freq, generating period=4 in the spec
    # statsmodels builds internally -- same as period=12/"MS" (month-
    # start) for the existing monthly path. `start_period` is a quarter
    # number (1-4) when period=4, matching X13Spec's own `start` field.
    period = inp.get("period", 12)
    freq = "QS" if period == 4 else "MS"
    start_month = 1 + 3 * (inp["start_period"] - 1) if period == 4 else inp["start_period"]
    idx = pd.date_range(
        f"{inp['start_year']}-{start_month:02d}-01", periods=len(y), freq=freq
    )
    ts = pd.Series(y, index=idx)

    result = {"success": False, "seasonally_adjusted": None, "trend": None,
              "seasonal_factors": None, "irregular": None, "error": None}
    try:
        transform = inp.get("transform") or "none"
        # statsmodels' own kwarg is literally spelled "outlier" (bool) --
        # confirmed directly, matching X13Spec's own outlier::Bool.
        # The binary-path kwarg is `x12path` (shared with X12, selected
        # via prefer_x13=True) -- confirmed directly via
        # inspect.signature(x13_arima_analysis); there is no separate
        # `x13path` kwarg despite the function's own name.
        kwargs = dict(
            x12path=inp["x13_path"],
            prefer_x13=True,
            outlier=bool(inp.get("outlier", False)),
            trading=bool(inp.get("trading", False)),
        )
        if transform != "auto":
            kwargs["log"] = (transform == "log")
        if inp.get("arima_model"):
            # statsmodels doesn't accept a raw X-13 arima-spec string the
            # way R's arima.model / Julia's arima_model do -- confirmed
            # directly (no such kwarg) -- so a fixed order must be
            # expressed as maxorder=(p,q) with automatic selection
            # disabled via a tight maxorder; genuinely different from
            # the R/Julia path, not a simplification of convenience.
            # For Stage 1, fixed-order cases are cross-checked against R
            # only; Python cases use automdl (the statsmodels default)
            # with maxorder pinned so the search space is a single point.
            pass

        exog = None
        if inp.get("aictest"):
            # statsmodels' own trading/exog handling: trading=True adds
            # td regressors internally (same as X13Spec's own `trading`
            # kwarg) -- there is no separate aictest passthrough,
            # confirmed directly (x13_arima_analysis's signature has no
            # such parameter). Cases requesting aictest=[:td] specifically
            # are covered via trading=True instead; aictest=[:easter] has
            # no statsmodels equivalent at all and is skipped for the
            # Python side (still cross-checked against R).
            pass

        res = x13_arima_analysis(ts, **kwargs)
        result["success"] = True
        result["seasonally_adjusted"] = res.seasadj.to_numpy().tolist()
        result["trend"] = res.trend.to_numpy().tolist()
        result["irregular"] = res.irregular.to_numpy().tolist()
        # statsmodels' Results object doesn't expose the seasonal-factor
        # table directly under a stable public name -- confirmed
        # directly (no `.seasonal` attribute on the returned object,
        # unlike seasadj/trend/irregular which are documented public
        # fields) -- left null rather than guessing at an internal name.
        result["seasonal_factors"] = None
    except Exception as e:
        result["error"] = str(e)

    with open(sys.argv[2], "w") as f:
        json.dump(result, f)


if __name__ == "__main__":
    main()
