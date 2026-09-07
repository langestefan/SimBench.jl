"""Pin the SimBench code enumeration.

The Julia suite asserted only that there are 246 codes, so a reordering in the middle of
the enumeration passed. This writes the ordered list itself.
"""

from __future__ import annotations

import simbench as sb

from common import FIXTURES, targets, write_csv


def main() -> None:
    codes = sb.collect_all_simbench_codes()
    shortened = sb.collect_all_simbench_codes(shortened=True)
    assert len(codes) == len(shortened)

    write_csv(
        FIXTURES / "codes.csv",
        ["index", "code", "code_shortened"],
        [(i, c, s) for i, (c, s) in enumerate(zip(codes, shortened, strict=True), 1)],
    )

    rows = []
    for name, kwargs in sorted(targets()["subsets"].items()):
        subset = sb.collect_all_simbench_codes(**kwargs)
        assert subset, f"subset {name} is empty"
        rows.extend((name, i, c) for i, c in enumerate(subset, 1))
    write_csv(FIXTURES / "code_subsets.csv", ["subset", "index", "code"], rows)


if __name__ == "__main__":
    main()
