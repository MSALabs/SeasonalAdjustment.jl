using Documenter
using SeasonalAdjustment

DocMeta.setdocmeta!(SeasonalAdjustment, :DocTestSetup, :(using SeasonalAdjustment); recursive = true)

makedocs(;
    modules = [SeasonalAdjustment],
    authors = "MSALabs",
    sitename = "SeasonalAdjustment.jl",
    format = Documenter.HTML(;
        canonical = "https://MSALabs.github.io/SeasonalAdjustment.jl",
        edit_link = "main",
        assets = String[],
    ),
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting_started.md",
        "API Reference" => "api.md",
    ],
    # doctest=:fix locally regenerates expected doctest output when you
    # deliberately change behaviour; leave as default (true) in CI so a
    # docstring example silently drifting out of date fails the build --
    # same policy as TSAnalytics.jl.
    doctest = true,
    checkdocs = :exports,  # build fails if an exported name has no docstring
)

deploydocs(;
    repo = "github.com/MSALabs/SeasonalAdjustment.jl",
    devbranch = "main",
)
