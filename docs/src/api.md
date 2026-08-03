```@meta
CurrentModule = SimBench
```

# API

Nothing is exported yet. Everything below is reached as `SimBench.name`.

## Module

```@docs
SimBench.SimBench
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
