using SimBench
using Documenter

DocMeta.setdocmeta!(SimBench, :DocTestSetup, :(using SimBench); recursive = true)

makedocs(;
    modules = [SimBench],
    authors = "Stefan de Lange <langestefan@msn.com>",
    sitename = "SimBench.jl",
    format = Documenter.HTML(;
        canonical = "https://langestefan.github.io/SimBench.jl",
        edit_link = "main",
        assets = String[],
    ),
    pages = [
        "Home" => "index.md",
        "API" => "api.md",
        "Contributing" => "contributing.md",
    ],
    checkdocs = :exports,
)

deploydocs(; repo = "github.com/langestefan/SimBench.jl", devbranch = "main")
