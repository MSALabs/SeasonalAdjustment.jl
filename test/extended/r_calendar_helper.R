# test/extended/r_calendar_helper.R
#
# Stage 2 of the extended test suite (see development-sequence.md's
# Post-W.4a addendum). Cross-validates the CALENDAR ENGINE (Easter
# computation, business-day arithmetic) against two independent R
# packages -- NOT against INDIA_NSE's own specific holiday data, which
# is sourced from NSE circulars and has no independent R-side source to
# check against either (see calendars.jl's own honest gap notes). Uses
# a plain weekends-only calendar on both sides so this is purely an
# engine/arithmetic check.
#
# - timeDate::Easter() -- a genuinely independent Easter computation
#   (different algorithm implementation than BusinessDays.jl's, which
#   this package's own easter_date reuses -- see calendars.jl's own
#   comment).
# - bizdays -- business-day arithmetic (is.bizday, businessdaysbetween-
#   equivalent, the four adjust conventions) against an equivalent
#   weekends-only calendar definition.
#
# Usage: Rscript r_calendar_helper.R <input.json> <output.json>
#
# Input JSON: {easter_years: [int], bizday_dates: [str "YYYY-MM-DD"],
#   between_cases: [{from,to}], adjust_cases: [{date,convention}]}
# convention is one of "following"/"preceding"/"modified_following"/
# "modified_preceding"/"unadjusted", matching Calendar's own adjust()
# convention symbols exactly (with underscores, translated to R's own
# dotted function names internally).
#
# Output JSON: {easter_dates: [str], bizday_results: [bool],
#   between_results: [int], adjust_results: [str]}

suppressMessages(library(timeDate))
suppressMessages(library(bizdays))
suppressMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
input <- fromJSON(args[1])

# bizdays' create.calendar has an implicit default date range --
# confirmed directly that a date outside it (e.g. 2087, comfortably
# within any real use of this package) makes is.bizday() error
# internally ("object 'cal.date' not found"), which jsonlite then
# serializes as a JSON `null` for that entry rather than a clean error.
# Set explicitly, wide enough to cover every date this file's grids use
# (Easter years go back to 1850 and forward to 2149).
cal <- create.calendar("weekendsonly", weekdays = c("saturday", "sunday"),
                        start.date = "1850-01-01", end.date = "2150-12-31")

# --- Easter -------------------------------------------------------
easter_dates <- character(0)
if (!is.null(input$easter_years) && length(input$easter_years) > 0) {
    e <- timeDate::Easter(input$easter_years)
    easter_dates <- format(as.Date(e), "%Y-%m-%d")
}

# --- is.bizday ------------------------------------------------------
bizday_results <- logical(0)
if (!is.null(input$bizday_dates) && length(input$bizday_dates) > 0) {
    dates <- as.Date(input$bizday_dates)
    bizday_results <- as.logical(is.bizday(dates, cal))
}

# --- businessdaysbetween (closed interval [from,to], matching
#     Calendar's own businessdaysbetween's inclusive-both-ends
#     semantics). Deliberately does NOT use bizdays()'s own `bizdays()`
#     function with a boundary correction -- confirmed directly, not
#     assumed, that its boundary convention doesn't reduce to a simple
#     "+1 when `to` is a business day" adjustment: for `bizdays(Mon,
#     Sun)` (5 real business days in the closed interval), `bizdays()`
#     itself returns 4 regardless of whether `to` lands on a weekend,
#     an off-by-one that a naive correction missed for exactly the
#     cases where `to` ISN'T a business day. Sidesteps the whole
#     question by counting directly via `is.bizday` over the explicit
#     date sequence -- the exact same reduction Calendar's own
#     `businessdaysbetween` uses (`count(isbusinessday, lo:Day(1):hi)`),
#     and `is.bizday` is already independently verified correct above,
#     so this can't introduce a NEW disagreement, only inherit a
#     already-confirmed-correct one.
between_results <- integer(0)
if (!is.null(input$between_cases) && nrow(input$between_cases) > 0) {
    between_results <- integer(nrow(input$between_cases))
    for (i in seq_len(nrow(input$between_cases))) {
        from_d <- as.Date(input$between_cases$from[i])
        to_d <- as.Date(input$between_cases$to[i])
        lo <- min(from_d, to_d)
        hi <- max(from_d, to_d)
        days <- seq(lo, hi, by = "day")
        between_results[i] <- sum(is.bizday(days, cal))
    }
}

# --- adjust conventions --------------------------------------------
adjust_results <- character(0)
if (!is.null(input$adjust_cases) && nrow(input$adjust_cases) > 0) {
    adjust_results <- character(nrow(input$adjust_cases))
    for (i in seq_len(nrow(input$adjust_cases))) {
        d <- as.Date(input$adjust_cases$date[i])
        conv <- input$adjust_cases$convention[i]
        result_d <- switch(conv,
            following = following(d, cal),
            preceding = preceding(d, cal),
            modified_following = modified.following(d, cal),
            modified_preceding = modified.preceding(d, cal),
            unadjusted = d,
            stop(paste("unknown convention:", conv))
        )
        adjust_results[i] <- format(as.Date(result_d), "%Y-%m-%d")
    }
}

result <- list(
    easter_dates = easter_dates,
    bizday_results = bizday_results,
    between_results = between_results,
    adjust_results = adjust_results
)
write(toJSON(result, auto_unbox = FALSE), file = args[2])
