# src/datasets.jl
#
# W.9 -- bundled datasets. See handoff/w9-datasets-handoff.md for the
# design (the referenced dataset-api-design.md itself was not attached
# to this session -- this file's design follows the handoff's own §3
# implementation sketch directly, cross-checked against the real CSV
# files rather than assumed).
#
# Plain committed CSV, not Artifacts.toml -- twelve-to-twenty kilobytes
# doesn't justify the hash/platform machinery Artifacts exists for (see
# the handoff's own §2 reasoning, which matches this package's existing
# W.1 artifact-vs-plain-file judgement calls). No CSV.jl dependency
# either: `Date(str)` parses ISO-8601 natively, which is the entire
# reason the on-disk format is `date,value` with an ISO date.

const _DATA_DIR = normpath(joinpath(@__DIR__, "..", "data"))

"""
    _read_dataset_csv(path) -> (date=Vector{Date}, value=Vector{Float64})

Reads a `date,value` CSV (header row, ISO-8601 date, `Float64` value) --
the one format every bundled dataset uses, confirmed directly against
each committed file rather than assumed from the handoff alone (`data/
iip_india.csv` originally shipped in a different raw format --quoted
headers, `"Mon YYYY"` dates -- and was normalized to this same shape at
authoring time specifically so this reader stays the only one needed;
see [`DatasetInfo`](@ref)'s own `iip_india` entry for that provenance
note).
"""
function _read_dataset_csv(path::AbstractString)
    lines = readlines(path)
    n = length(lines) - 1
    dates = Vector{Date}(undef, n)
    values = Vector{Float64}(undef, n)
    for i in 1:n
        d, v = split(lines[i+1], ',')
        dates[i] = Date(d)
        values[i] = parse(Float64, v)
    end
    return (date = dates, value = values)
end

"""
    DatasetInfo

Provenance for one bundled dataset (`dataset_info(name)`) -- `name`/
`title`/`source`/`url`/`licence`/`citation`/`frequency`/`n`/`span`/
`units`/`retrieved`/`notes`/`kind`. `kind` is one of `:published`
(a real, sourced series), `:derived` (built from another shipped
dataset -- `appliance_q` from `appliance`), or `:synthetic` (none
shipped yet; reserved for handoff §10.1/§10.2's still-outstanding
teaching examples) -- added now rather than deferred, since this
session already ships one `:derived` dataset that needs to say so
structurally, not just in prose.
"""
struct DatasetInfo
    name::String
    title::String
    source::String
    url::String
    licence::String
    citation::String
    frequency::Int
    n::Int
    span::Tuple{Date,Date}
    units::String
    retrieved::Union{Date,Nothing}
    notes::String
    kind::Symbol
end

function Base.show(io::IO, ::MIME"text/plain", d::DatasetInfo)
    println(io, d.title, " (\"", d.name, "\")")
    println(io, "  Source:     ", d.source)
    isempty(d.url) || println(io, "  URL:        ", d.url)
    println(io, "  Licence:    ", d.licence)
    println(io, "  Kind:       ", d.kind)
    println(io, "  Frequency:  ", d.frequency, " (", d.frequency == 12 ? "monthly" : d.frequency == 4 ? "quarterly" : "n=$(d.frequency)", ")")
    println(io, "  N:          ", d.n)
    println(io, "  Span:       ", d.span[1], " .. ", d.span[2])
    println(io, "  Units:      ", d.units)
    d.retrieved !== nothing && println(io, "  Retrieved:  ", d.retrieved)
    println(io, "  Citation:   ", d.citation)
    isempty(d.notes) || println(io, "  Notes:      ", d.notes)
end

# ---------------------------------------------------------------------
# The registry -- the single source of truth §9 of the handoff refers
# to. datasets()/dataset()/broadcasting/every sink all derive from this
# one Dict; adding a dataset later touches nothing else in this file.
# ---------------------------------------------------------------------

const _REGISTRY = Dict{String,DatasetInfo}(
    "airline" => DatasetInfo(
        "airline",
        "International airline passengers",
        "Box & Jenkins (1976), Series G",
        "",
        "Public domain",
        "Box, G.E.P. and Jenkins, G.M. (1976). Time Series Analysis: " *
        "Forecasting and Control. Holden-Day. Series G.",
        12, 144, (Date(1949, 1, 1), Date(1960, 12, 1)),
        "thousands of passengers", nothing,
        "The canonical seasonal adjustment example. Strongly multiplicative; " *
        "X-13 selects a log transform. Also this package's own verification " *
        "baseline (handoff/verification/airline_baseline/), so book output " *
        "and test fixtures agree by construction. X-13 detects a real, " *
        "non-obvious additive outlier at May 1951 under this package's own " *
        "fixture spec (values 163/172/178 for Apr/May/Jun -- not visually " *
        "obvious; detection runs on regARIMA residuals after differencing, " *
        "not levels). See test/test_datasets.jl's own regression test for it.",
        :published,
    ),
    "appliance" => DatasetInfo(
        "appliance",
        "Monthly retail sales of household appliance stores",
        "US Census Bureau, X-13ARIMA-SEATS Reference Manual v1.1, Ch. 3",
        "https://www.census.gov/data/software/x13as.html",
        "Public domain (US federal government work)",
        "U.S. Census Bureau (2015). X-13ARIMA-SEATS Reference Manual, " *
        "Version 1.1, Chapter 3, Examples 3.1-3.4.",
        12, 192, (Date(1972, 7, 1), Date(1988, 6, 1)),
        "unknown", nothing,
        "The manual's own worked example, chosen because its spectrum reveals " *
        "a trading-day component. Units are not stated in the source -- " *
        "recorded as \"unknown\" rather than guessed. December (1.52x the " *
        "annual mean) dominates the seasonal shape, a genuinely different " *
        "structure from airline's summer peak -- the contrast is deliberate.",
        :published,
    ),
    "appliance_q" => DatasetInfo(
        "appliance_q",
        "Monthly retail sales of household appliance stores, aggregated to quarters",
        "Derived from \"appliance\" (US Census Bureau, X-13ARIMA-SEATS Reference Manual v1.1, Ch. 3)",
        "https://www.census.gov/data/software/x13as.html",
        "Public domain (US federal government work)",
        "U.S. Census Bureau (2015). X-13ARIMA-SEATS Reference Manual, " *
        "Version 1.1, Chapter 3, Examples 3.1-3.4 (quarterly aggregation " *
        "of the Bureau's own monthly series, not itself a Census product).",
        4, 64, (Date(1972, 7, 1), Date(1988, 4, 1)),
        "unknown", nothing,
        "DERIVED, not an independently published series: appliance's 192 " *
        "months summed into 64 quarters (sums preserved exactly). Exists to " *
        "exercise period=4 -- quarterly dates, Q1-Q4 tick labels, quarterly " *
        "outlier labels, the quarterly-scaled seasonal_ma in filters(). " *
        "Weak for anything substantive: aggregation washes out the " *
        "trading-day and moving-holiday structure that makes quarterly " *
        "adjustment genuinely interesting. A real published quarterly " *
        "series would be better and should replace this when one is sourced.",
        :derived,
    ),
    "iip_india" => DatasetInfo(
        "iip_india",
        "India Index of Industrial Production (General), base 2011-12=100",
        "Ministry of Statistics and Programme Implementation (MOSPI), Government of India",
        "",
        "Government of India open data -- exact redistribution terms not " *
        "independently verified this session (flagged, not silently assumed " *
        "\"public domain\"; confirm before wider redistribution)",
        "Ministry of Statistics and Programme Implementation, Government of " *
        "India. Index of Industrial Production, General Index, base 2011-12=100.",
        12, 180, (Date(2011, 4, 1), Date(2026, 3, 1)),
        "index (2011-12=100)", nothing,
        "The real Indian monthly series this package's own India-calendar " *
        "layer (INDIA_NSE, custom_holiday_regressor) needs a genuine worked " *
        "example against -- resolves the licensing blocker the source " *
        "handoff (w9-datasets-handoff.md §7.2) left open, though the exact " *
        "redistribution terms were not independently re-verified here; " *
        "revisit before any wider publication. Carries a real, dramatic " *
        "COVID level shift (April 2020: 54.0, down from 117.2 in March -- " *
        "the sharpest single-month move in the series), which also happens " *
        "to resolve handoff §10.5's separately-flagged need for a real " *
        "level-shift example. Column normalized from the source's own " *
        "\"in.iip.2011.12\" / \"Mon YYYY\" format to this package's standard " *
        "date,value/ISO-8601 shape at authoring time -- see " *
        "_read_dataset_csv's own docstring.",
        :published,
    ),
)

const _CACHE = Dict{String,NamedTuple}()

function _dataset_table(name::AbstractString)
    key = String(name)
    haskey(_REGISTRY, key) || throw(ArgumentError(
        "unknown dataset $(repr(key)). Available: $(join(sort(collect(keys(_REGISTRY))), ", "))",
    ))
    return get!(_CACHE, key) do
        _read_dataset_csv(joinpath(_DATA_DIR, key * ".csv"))
    end
end

"""
    dataset(name) -> (date=Vector{Date}, value=Vector{Float64})
    dataset(name, sink)

`name` is `"airline"`/`:airline`/etc -- see [`datasets`](@ref) for the
full list. Returns a plain `NamedTuple` (a Tables.jl column table with
no `Tables.jl` dependency of its own) by default; a `deepcopy` of the
package's own cached copy, so mutating what you get back can't corrupt
a later call in the same session (the two-arg `sink` form skips this --
a sink materialises its own storage, e.g. `dataset("airline", DataFrame)`).

**No `dataset(names::AbstractVector)` method, deliberately.**
Broadcasting is the vector story (`dataset.(["airline", "appliance"])`)
-- if both existed, `dataset(names)` and `dataset.(names)` would be
different operations spelled almost identically.

**Sink failures pass through unchanged.** `dataset("airline", Vector)`
fails with `MethodError: no method matching Vector(::NamedTuple...)`,
which names the real problem -- no custom fallback error wraps it.

Confirmed sinks: `DataFrame`, `TSFrame` (its own docs confirm
`CSV.read(path, TSFrame)`, i.e. any Tables.jl source), `Tables.rowtable`,
`Tables.matrix` (mixed `Date`/`Float64` gives `Matrix{Any}`). `TimeArray`
as a BARE sink is unverified -- use `x -> TimeArray(x; timestamp=:date)`
if the bare form needs a hint.

```julia
result = x13(dataset("airline"))   # start is inferred from tsindex, see below
```
"""
dataset(name::AbstractString) = deepcopy(_dataset_table(name))
dataset(name::AbstractString, sink) = sink(_dataset_table(name))
dataset(name::Symbol, args...) = dataset(String(name), args...)

"""
    datasets() -> Vector{String}
    datasets(sink)

Every bundled dataset's name, sorted (`"airline"`, `"appliance"`,
`"appliance_q"`, `"iip_india"`) -- or, with a `sink`, a Tables.jl table
of every dataset's own metadata (name/title/frequency/n/span/units/
licence/kind), one row per dataset.
"""
datasets() = sort(collect(keys(_REGISTRY)))
datasets(sink) = sink(_metadata_table())

function _metadata_table()
    infos = [_REGISTRY[k] for k in datasets()]
    return (
        name = [i.name for i in infos],
        title = [i.title for i in infos],
        frequency = [i.frequency for i in infos],
        n = [i.n for i in infos],
        start = [i.span[1] for i in infos],
        stop = [i.span[2] for i in infos],
        units = [i.units for i in infos],
        licence = [i.licence for i in infos],
        kind = [i.kind for i in infos],
    )
end

"""
    dataset_info(name) -> DatasetInfo

Full provenance for one bundled dataset -- source, licence, citation,
span, and (for `iip_india`) an explicit note on what was and wasn't
independently re-verified this session. Answers "may I publish a chart
of this" without re-deriving it from `notes` prose each time.
"""
dataset_info(name::AbstractString) = _REGISTRY[String(name)]
dataset_info(name::Symbol) = dataset_info(String(name))

# ---------------------------------------------------------------------
# tsvalues/tsindex extensions -- what makes `x13(dataset("airline"))`
# work at all. TSAnalytics.jl's own fallback (`tsvalues(x) =
# collect(Float64, x)`) would try to convert the WHOLE NamedTuple
# (2 elements: a Vector{Date} and a Vector{Float64}) to Float64 and
# fail outright without this -- confirmed directly by reading
# TSAnalytics' own interface.jl rather than assumed.
# ---------------------------------------------------------------------

TSAnalytics.tsvalues(d::NamedTuple{(:date, :value)}) = d.value
TSAnalytics.tsindex(d::NamedTuple{(:date, :value)}) = d.date
