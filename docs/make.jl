using Documenter
using SeasonalAdjustment

DocMeta.setdocmeta!(SeasonalAdjustment, :DocTestSetup, :(using SeasonalAdjustment); recursive = true)

include("pages.jl")

makedocs(;
    modules = [SeasonalAdjustment],
    authors = "MSALabs",
    sitename = "SeasonalAdjustment.jl",
    format = Documenter.HTML(;
        canonical = "https://MSALabs.github.io/SeasonalAdjustment.jl",
        edit_link = "main",
        assets = String[],
        # Sidebar defaults to collapsed except for whichever section is
        # currently active (Documenter auto-expands the active page's own
        # branch regardless of this setting) -- landing on Home therefore
        # shows Home expanded and every other section collapsed to just
        # its label, exactly the requested landing state.
        collapselevel = 1,
    ),
    pages = PAGES,
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
