```@meta
CurrentModule = SimBench
```

# API

The core workflow is exported: [`SimBenchGrid`](@ref SimBench.SimBenchGrid),
[`SimBenchCode`](@ref SimBench.SimBenchCode),
[`all_simbench_codes`](@ref SimBench.all_simbench_codes),
[`read_grid`](@ref SimBench.read_grid),
[`powermodels_data`](@ref SimBench.powermodels_data),
[`absolute_profiles`](@ref SimBench.absolute_profiles),
[`apply_profile!`](@ref SimBench.apply_profile!) and
[`apply_study_case!`](@ref SimBench.apply_study_case!). Everything else is reached as
`SimBench.name`.

## Module

```@docs
SimBench.SimBench
```

## Grids

```@docs
SimBench.SimBenchGrid
SimBench.read_grid
SimBench.scenario
SimBench.clear_scenario_cache!
```

## Grid extraction

```@docs
SimBench.relevant_subnets
SimBench.extract_tables
SimBench.extract_table
SimBench.hv_subnet_of
SimBench.lv_subnets_of
SimBench.bus_bus_switch_rows
SimBench.GRID_NUMBERS
SimBench.TWO_SIDED_TABLES
```

## PowerModels conversion

```@docs
SimBench.powermodels_data
SimBench.attach_coordinates!
SimBench.DEFAULT_BASE_MVA
SimBench.DEFAULT_ANGLE_LIMIT
```

## Profiles and study cases

```@docs
SimBench.absolute_profiles
SimBench.apply_profile!
SimBench.apply_study_case!
SimBench.filter_unapplied_profiles!
SimBench.filter_study_cases!
SimBench.PROFILE_ELEMENTS
```

## Topology

```@docs
SimBench.Topology
SimBench.resolve_topology
SimBench.bus_of
SimBench.multi_switch_aux_nodes
```

## SimBench codes

```@docs
SimBench.SimBenchCode
SimBench.all_simbench_codes
SimBench.is_complete_data
SimBench.complete_data_code
SimBench.complete_grid_code
```

### Code space

```@docs
SimBench.HV_LEVELS
SimBench.LV_LEVELS
SimBench.VOLTAGE_LEVEL_PAIRS
SimBench.HV_TYPES
SimBench.LV_GRIDS
SimBench.LV_GRIDS_SHORTENED
```

## Reading CSV tables

```@docs
SimBench.read_table
SimBench.read_tables
SimBench.empty_table
SimBench.CSV_DELIM
SimBench.CSV_MISSING
SimBench.PROFILE_TIME_COLUMN
SimBench.PROFILE_TIME_FORMAT
```

## Voltage levels

```@docs
SimBench.voltlvl_int
SimBench.voltlvl_name
SimBench.voltlvl_from_vn_kv
SimBench.VOLTLVL_NAMES
SimBench.VN_KV_LIMITS
```

## Dataset location

```@docs
SimBench.data_dir
SimBench.artifact_data_dir
SimBench.set_data_dir!
SimBench.reset_data_dir!
SimBench.scenario_path
SimBench.complete_data_folder
SimBench.table_path
SimBench.SimBenchDataError
SimBench.DATA_DIR_ENV
SimBench.SCENARIOS
SimBench.DATASET_VERSION
SimBench.DATASET_RELEASE
SimBench.ARTIFACT_SUBPATH
```

## Table inventory

```@docs
SimBench.csv_tablenames
SimBench.csv_filename
SimBench.available_tables
SimBench.missing_tables
SimBench.has_fixed_schema
SimBench.table_columns
SimBench.table_coltypes
```

### Table groups

```@docs
SimBench.ELEMENT_TABLES
SimBench.PROFILE_TABLES
SimBench.TYPE_TABLES
SimBench.CASE_TABLES
SimBench.RESULT_TABLES
SimBench.ALL_TABLES
```

### Availability in the published dataset

```@docs
SimBench.REQUIRED_TABLES
SimBench.SCENARIO_TABLES
SimBench.UNUSED_TABLES
SimBench.OPTIONAL_TABLES
```
