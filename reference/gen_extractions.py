"""Pin grid extraction: per table row counts and element id digests.

Mirrors SimBench.extract_tables, which is the port of get_extracted_csv_data. The row
counts were already pinned by hand in the Julia suite; the digests are what closes the
gap, since equal counts do not mean equal elements.
"""

from __future__ import annotations

from simbench.networks.extract_simbench_grids_from_csv import (
    complete_data_path,
    get_extracted_csv_data,
    get_relevant_subnets,
    get_simbench_code_and_parameters,
)

from common import FIXTURES, digest, targets, write_csv


def extract(code: str) -> dict:
    """The extracted tables for `code`, before any profile or load case filtering."""
    _, parameters = get_simbench_code_and_parameters(code)
    input_path = complete_data_path(parameters[5])
    relevant_subnets = get_relevant_subnets(parameters, input_path)
    return get_extracted_csv_data(relevant_subnets, input_path)


def main() -> None:
    rows = []
    for code in targets()["extraction_codes"]:
        print(f"  extracting {code}")
        tables = extract(code)
        for table, frame in sorted(tables.items()):
            # Only the element tables carry an id. Profile, type and study case tables
            # are keyed differently and the Julia tests read them with nrows = 1, so
            # their counts would not be comparable anyway.
            if "id" not in frame.columns:
                continue
            ids = [str(i) for i in frame["id"].tolist()]
            rows.append(
                (
                    code,
                    table,
                    len(frame),
                    digest(ids),
                    digest(sorted(ids)),
                )
            )

    write_csv(
        FIXTURES / "extractions.csv",
        ["code", "table", "nrows", "id_digest", "id_digest_sorted"],
        rows,
    )


if __name__ == "__main__":
    main()
