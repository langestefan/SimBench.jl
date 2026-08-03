```@meta
CurrentModule = SimBench
```

# API

Nothing is exported yet. Everything below is reached as `SimBench.name`.

## Module

```@docs
SimBench.SimBench
```

## Grids

```@docs
SimBench.SimBenchGrid
SimBench.read_grid
SimBench.scenario
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
SimBench.set_data_dir!
SimBench.reset_data_dir!
SimBench.scenario_path
SimBench.complete_data_folder
SimBench.table_path
SimBench.SimBenchDataError
SimBench.DATA_DIR_ENV
SimBench.SCENARIOS
SimBench.DATASET_VERSION
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
