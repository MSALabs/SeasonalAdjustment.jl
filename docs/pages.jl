# docs/pages.jl -- the Documenter `pages` tree, factored out of make.jl so
# local/scratch build scripts can `include` the real, current list instead
# of carrying their own copy that silently goes stale as chapters are added.

const PAGES = [
    "Home" => "index.md",
    "Getting Started" => "getting_started.md",
    "Introduction to Seasonal Adjustment" => [
        "introduction/01-why-adjust.md",
        "introduction/02-decomposition.md",
        "introduction/03-origins.md",
        "introduction/04-x11-by-hand.md",
        "introduction/05-trend-filters.md",
        "introduction/06-seasonal-filters.md",
        "introduction/07-bcd-tables.md",
        "introduction/08-extreme-values-modes.md",
        "introduction/09-end-of-series.md",
        "introduction/16-why-so-many-diagnostics.md",
        "introduction/17-m-statistics.md",
        "introduction/18-residual-seasonality.md",
        "introduction/19-model-adequacy.md",
        "introduction/20-stability-revisions.md",
        "introduction/A-checklist.md",
    ],
    "API Reference" => "api.md",
]
