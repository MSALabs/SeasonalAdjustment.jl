# docs/pages.jl -- the Documenter `pages` tree, factored out of make.jl so
# local/scratch build scripts can `include` the real, current list instead
# of carrying their own copy that silently goes stale as chapters are added.

const PAGES = [
    "Home" => "index.md",
    "Getting Started" => "getting_started.md",
    "Introduction to Seasonal Adjustment" => [
        "introduction/09-end-of-series.md",
    ],
    "API Reference" => "api.md",
]
