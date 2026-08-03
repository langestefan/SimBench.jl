using SimBench
using Documenter
using DocumenterVitepress

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
