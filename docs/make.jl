using Documenter
using SeasonalAdjustment

makedocs(
    sitename = "SeasonalAdjustment.jl",
    modules = [SeasonalAdjustment],
    pages = [
        "Home" => "index.md",
    ],
)

deploydocs(
    repo = "github.com/MSALabs/SeasonalAdjustment.jl.git",
)
