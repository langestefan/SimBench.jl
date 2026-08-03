# Voltage level classification.
#
# Ported from simbench/converter/voltLvl.py.

"""
Voltage level names, indexed by their SimBench level number.

Odd numbers are the levels themselves; even numbers are the boundaries between two
levels, used for elements such as transformers that span them.
"""
const VOLTLVL_NAMES = ("EHV", "EHV-HV", "HV", "HV-MV", "MV", "MV-LV", "LV")

const _VOLTLVL_ALIASES = Dict{String, Int}(
    "EHV" => 1, "UHV" => 1,
    "EHV-HV" => 2, "UHV-HV" => 2, "EHVHV" => 2, "UHVHV" => 2,
    "HV" => 3,
    "HV-MV" => 4, "HVMV" => 4,
    "MV" => 5,
    "MV-LV" => 6, "MVLV" => 6,
    "LV" => 7,
)

"""
Nominal voltage boundaries in kV separating EHV from HV, HV from MV, and MV from LV.

A bus belongs to the higher level when its nominal voltage is strictly above the bound.
"""
const VN_KV_LIMITS = (145.0, 60.0, 1.0)

"""
    voltlvl_int(level) -> Int

SimBench level number of a voltage level given by name or number.

Names are case-insensitive and accept both the hyphenated and concatenated spellings of
a boundary level, e.g. `"HV-MV"` and `"HVMV"`.

# Examples
```jldoctest
julia> SimBench.voltlvl_int("MV"), SimBench.voltlvl_int("hv-mv"), SimBench.voltlvl_int(7)
(5, 4, 7)
```
"""
function voltlvl_int(level::AbstractString)
    n = get(_VOLTLVL_ALIASES, uppercase(level), nothing)
    n === nothing || return n
    parsed = tryparse(Int, level)
    parsed === nothing && throw(ArgumentError("unknown voltage level \"$level\""))
    return voltlvl_int(parsed)
end

function voltlvl_int(level::Integer)
    1 <= level <= 7 ||
        throw(ArgumentError("voltage level number must be in 1:7, got $level"))
    return Int(level)
end

"""
    voltlvl_name(level) -> String

Voltage level name of a level given by name or number.

# Examples
```jldoctest
julia> SimBench.voltlvl_name(5), SimBench.voltlvl_name("mv")
("MV", "MV")
```
"""
voltlvl_name(level) = VOLTLVL_NAMES[voltlvl_int(level)]

"""
    voltlvl_from_vn_kv(vn_kv) -> Int

SimBench level number of a bus with nominal voltage `vn_kv` in kV.

Returns an odd number, since a single bus sits within one level rather than on a
boundary: 1 for EHV above 145 kV, 3 for HV above 60 kV, 5 for MV above 1 kV, and 7 for
LV at or below 1 kV.

# Examples
```jldoctest
julia> SimBench.voltlvl_from_vn_kv.([380.0, 110.0, 20.0, 0.4])
4-element Vector{Int64}:
 1
 3
 5
 7
```
"""
function voltlvl_from_vn_kv(vn_kv::Real)
    level = 1
    for limit in VN_KV_LIMITS
        vn_kv <= limit && (level += 2)
    end
    return level
end
