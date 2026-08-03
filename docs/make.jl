using SimBench
using Documenter
using DocumenterVitepress

# Load the packages the executed example blocks use here, outside Documenter's output
# capture. PowerModels' Memento logger binds its stream when the package first loads;
# loading inside a captured block ties it to that block's pipe, and every later log
# write, such as the one PowerModels.silence() emits, hits a closed stream.
#
# Memento is gone from PowerModels 0.21.6, which switched to Logging.jl, but this
# environment cannot resolve it yet: 0.21.6 requires JSON 1, while VegaLite, which
# PowerPlots plots through, caps JSON below 1. Once VegaLite allows JSON 1 the
# resolver picks 0.21.6 on its own and this preload becomes harmless.
using PowerModels
using PowerPlots
using VegaLite

DocMeta.setdocmeta!(SimBench, :DocTestSetup, :(using SimBench); recursive = true)

makedocs(;
    modules = [SimBench],
    authors = "Stefan de Lange <langestefan@msn.com>",
    sitename = "SimBench.jl",
    format = MarkdownVitepress(;
        repo = "github.com/langestefan/SimBench.jl",
        devbranch = "main",
        devurl = "dev",
    ),
    pages = [
        "Home" => "index.md",
        "Tutorial" => "tutorial.md",
        "Conversion options" => "conversion.md",
        "Plotting" => "plotting.md",
        "API" => "api.md",
        "Contributing" => "contributing.md",
    ],
    checkdocs = :exports,
)

DocumenterVitepress.deploydocs(;
    repo = "github.com/langestefan/SimBench.jl",
    devbranch = "main",
    push_preview = true,
)
