# Reading the reference fixtures under test/references/.
#
# The fixtures are captured from the Python reference implementation by
# reference/generate_all.py; see reference/README.md for how to regenerate them. Reading
# a fixture needs no dataset, so comparisons that are purely fixture based stay
# available even when the dataset itself is not.

using CSV: CSV
using DataFrames: DataFrame
using SHA: sha256

const REFERENCE_DIR = joinpath(@__DIR__, "references")

"""Path to the reference fixture named by `parts`."""
reference_path(parts...) = joinpath(REFERENCE_DIR, parts...)

"""Whether the reference fixture named by `parts` is present."""
have_reference(parts...) = isfile(reference_path(parts...))

"""Read the reference fixture named by `parts` as a `DataFrame`."""
read_reference(parts...) = DataFrame(CSV.File(reference_path(parts...)))

"""
    id_digest(ids) -> String

Short digest of a sequence of element ids. Must match `digest` in
`reference/common.py`: the ids joined by newlines, SHA256, first 16 hex characters.
"""
id_digest(ids) = bytes2hex(sha256(join(ids, "\n")))[1:16]

"""
The per-grid reference manifest, or `nothing` when the fixtures are absent.

Carries the provenance of the capture, the counts the partition checks need, and the
per-grid tolerances, so a grid that legitimately needs looser bounds says so in the data
rather than in a branch in the test.
"""
const MANIFEST = have_reference("manifest.csv") ? read_reference("manifest.csv") : nothing
