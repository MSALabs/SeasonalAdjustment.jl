# test/extended/r_helper.R
#
# Stage 1 of the extended, R/Python-cross-validated test suite (see
# development-sequence.md's Post-W.4a section for the full writeup).
# Runs one seasonal-adjustment case through R's `seasonal::seas()` --
# pointed at THIS package's own already-verified x13ashtml binary via
# X13_PATH, not the (non-functional, confirmed directly on this
# session's own machine) conda-forge-bundled one -- and writes the
# result as JSON, so Julia can drive R the same way it already drives
# the real binary directly (see src/run.jl's own subprocess-invocation
# style, which this mirrors).
#
# Usage: Rscript r_helper.R <input.json> <output.json>
#
# Input JSON fields (all optional except y/start_year/start_period):
#   y: [numbers], start_year/start_period: integers
#   transform: "none"|"log"|"auto"|null
#   arima_model: "(0 1 1)(0 1 1)" string, or null to let automdl search
#   outlier: true/false
#   seats: true/false
#   trading: true/false
#   regression_variables: ["td", "easter[1]", ...] (R-syntax passthrough)
#   aictest: ["td", "easter"] or [] -- see the note on regression.aictest
#     below; MUST be passed explicitly (as [] when not wanted) or R's own
#     default silently adds td+easter regression effects Julia's spec
#     wouldn't have, corrupting the comparison -- confirmed directly
#     this session (a genuinely different result, not a rounding issue,
#     traced via seasonal's own `static()` spec-inspection function to
#     regression.aictest defaulting to something non-NULL even when
#     regression.variables=NULL is passed).
#
# Output JSON: {success, seasonally_adjusted, trend, seasonal_factors,
#               irregular, error}
# -- deliberately the same shape as Julia's own X13Result fields, so
# comparison code on the Julia side doesn't need a translation layer.

suppressMessages(library(seasonal))
suppressMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
input <- fromJSON(args[1])

y <- ts(input$y, start = c(input$start_year, input$start_period), frequency = 12)

# Build seas() arguments to mirror X13Spec/render's own block structure
# as closely as possible -- see this session's own knob-by-knob
# verification (development-sequence.md) for why each mapping below is
# what it is, not guessed:
#   transform.function -- direct passthrough, same three values X13Spec
#     itself accepts (none/log/auto).
#   arima.model -- R's own arima.model argument takes the identical
#     X-13 spec-string syntax X13Spec's arima_model field does
#     ("(p d q)(P D Q)") -- confirmed directly, no translation needed.
#     NULL triggers automdl, matching X13Spec's own automdl=true when
#     arima_model=nothing.
#   outlier=NULL -- confirmed directly this disables outlier detection
#     entirely (matching X13Spec's outlier=false); leaving outlier at
#     its own seas() default enables it (matching outlier=true).
#   x11="" vs omitted -- confirmed directly: passing x11="" selects the
#     X-11 decomposition path (matching seats=false); omitting it
#     entirely selects SEATS (matching seats=true).
#   regression.variables=NULL -- confirmed directly this suppresses the
#     regression block entirely; a character vector matches
#     X13Spec's regression_variables passthrough exactly (R-style raw
#     variable names, same as this package's own R-inspired design).
result <- tryCatch({
    # `trading` (Julia's own shorthand for adding "td" to
    # regression_variables, mirrored here) must be folded into the same
    # variables list BEFORE building seas_args -- confirmed directly
    # that a `trading` JSON field with no corresponding R-side handling
    # is silently ignored (R's output was identical with trading=true
    # and trading=false, a real bug in this script found only by
    # comparing against Julia's own genuinely-different output for the
    # same nominal case, not a discrepancy in Julia).
    reg_vars <- if (is.null(input$regression_variables)) character(0) else input$regression_variables
    if (isTRUE(input$trading) && !("td" %in% reg_vars)) {
        reg_vars <- c(reg_vars, "td")
    }

    # outlier=NULL, present as a REAL list element (only true when built
    # directly inside the list() constructor -- confirmed directly that
    # `existing_list$outlier <- NULL` afterwards REMOVES the key instead
    # of setting it, R's own documented `$<-`-with-NULL removal
    # semantics, the opposite of what's needed here), disables outlier
    # detection, matching X13Spec's outlier=false. To ENABLE it, the
    # argument must be entirely ABSENT from the seas() call -- passing
    # outlier=NA is invalid (confirmed directly: "missing value where
    # TRUE/FALSE needed") -- so the two cases build genuinely different
    # list literals rather than mutating one afterwards.
    base_args <- list(
        x = y,
        transform.function = if (is.null(input$transform)) "none" else input$transform,
        regression.variables = if (length(reg_vars) == 0) NULL else reg_vars,
        # MUST be set explicitly -- see the module comment above.
        regression.aictest = if (is.null(input$aictest) || length(input$aictest) == 0) NULL else input$aictest
    )
    seas_args <- if (isTRUE(input$outlier)) base_args else c(base_args, list(outlier = NULL))
    if (!is.null(input$arima_model)) {
        seas_args$arima.model <- input$arima_model
    }
    if (!isTRUE(input$seats)) {
        seas_args$x11 <- ""
    }

    m <- do.call(seas, seas_args)

    if (isTRUE(input$seats)) {
        sa <- as.numeric(final(m))
        trend_v <- as.numeric(series(m, "s12"))
        seasonal_v <- as.numeric(series(m, "s10"))
        irregular_v <- as.numeric(series(m, "s13"))
    } else {
        sa <- as.numeric(final(m))
        trend_v <- as.numeric(series(m, "d12"))
        seasonal_v <- as.numeric(series(m, "d10"))
        irregular_v <- as.numeric(series(m, "d13"))
    }

    list(
        success = TRUE,
        seasonally_adjusted = sa,
        trend = trend_v,
        seasonal_factors = seasonal_v,
        irregular = irregular_v,
        error = NULL
    )
}, error = function(e) {
    list(success = FALSE, seasonally_adjusted = NULL, trend = NULL,
         seasonal_factors = NULL, irregular = NULL, error = conditionMessage(e))
})

write(toJSON(result, auto_unbox = TRUE, null = "null"), file = args[2])
