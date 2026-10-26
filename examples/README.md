# Examples

Runnable scripts that use the package end to end. They live in their own environment, so
nothing here is a dependency of SimBench.jl itself.

| Script | What it does |
| ----------------------- | ------------------------------------------------------------ |
| `interactive_grid.jl` | Reads a grid, applies a profile, solves it and plots it |

The environment resolves SimBench.jl from this checkout and
[PowerPlotsMakie.jl](https://github.com/langestefan/PowerPlotsMakie.jl) from a sibling one,
through the `[sources]` section of `examples/Project.toml`, which needs Julia 1.11 or
newer. Clone PowerPlotsMakie.jl next to this repository, or point that entry somewhere
else:

```bash
git clone https://github.com/langestefan/PowerPlotsMakie.jl ../PowerPlotsMakie.jl
julia --project=examples -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()'
julia --project=examples examples/interactive_grid.jl
```

`interactive_grid.jl` opens a GLMakie window: the two menus below the plot choose the grid
and the routing algorithm, and the buses can be dragged, pinned and relaxed. Grids are
read, converted and solved the first time they are picked, so the first view of each one
takes a moment.

The dataset downloads itself on first use; see the [README](../README.md) for how to point
at a local copy instead.
