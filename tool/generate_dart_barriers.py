#!/usr/bin/env python3
"""Generate final Dart barrier sets with per-tileset exclusions applied.

Reads the raw index files from the first scan, applies exclusion rules,
and outputs clean Dart code ready to paste into predefined_tilesets.dart.

Usage:
    python3 tool/generate_dart_barriers.py
"""

import ast
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "tool"


def read_indices(tileset_id: str) -> list[int]:
    """Read raw indices from the scan output file."""
    path = TOOL / f"{tileset_id}_indices.txt"
    with open(path) as f:
        for line in f:
            if line.startswith("All indices:"):
                return ast.literal_eval(line.split(":", 1)[1].strip())
    raise ValueError(f"Could not find indices in {path}")


def filter_by_rows(indices: list[int], columns: int,
                   exclude_rows: set[int] | None = None,
                   include_rows: set[int] | None = None) -> list[int]:
    """Filter indices by row inclusion/exclusion rules."""
    result = []
    for idx in indices:
        row = idx // columns
        if exclude_rows and row in exclude_rows:
            continue
        if include_rows and row not in include_rows:
            continue
        result.append(idx)
    return result


def find_contiguous_ranges(indices: list[int]) -> list[tuple[int, int]]:
    """Group sorted indices into (start, end) inclusive ranges."""
    if not indices:
        return []
    ranges = []
    start = end = indices[0]
    for i in indices[1:]:
        if i == end + 1:
            end = i
        else:
            ranges.append((start, end))
            start = end = i
    ranges.append((start, end))
    return ranges


def format_dart_set(var_name: str, indices: list[int], columns: int) -> str:
    """Format as compact Dart Set<int> with range-based for loops."""
    ranges = find_contiguous_ranges(sorted(indices))

    lines = [f"final Set<int> _{var_name}Barriers = {{"]

    for start, end in ranges:
        count = end - start + 1
        start_row = start // columns
        end_row = end // columns

        if count >= 10:
            lines.append(
                f"  for (int i = {start}; i <= {end}; i++) i, "
                f"// rows {start_row}–{end_row} ({count} tiles)"
            )
        elif count >= 4:
            # Short range, still use for loop
            lines.append(
                f"  for (int i = {start}; i <= {end}; i++) i, // row {start_row}"
            )
        else:
            vals = ", ".join(str(i) for i in range(start, end + 1))
            lines.append(f"  {vals}, // row {start_row}")

    lines.append("};")
    return "\n".join(lines)


def main():
    # ── modern_office (16×53) ─────────────────────────────────────────
    # All non-empty = barrier. Office furniture blocks movement.
    mo = read_indices("modern_office")
    print(f"// modern_office: {len(mo)} barrier tiles out of {16*53}")
    print(format_dart_set("modernOffice", mo, 16))
    print()

    # ── ext_terrains (32×74) ──────────────────────────────────────────
    # MANUAL: Only fences (rows 70–73, right side).
    # Terrain surfaces (grass, dirt, paths, water) are walkable.
    et = read_indices("ext_terrains")
    et_fences = filter_by_rows(et, 32, include_rows=set(range(70, 74)))
    print(f"// ext_terrains: {len(et_fences)} barrier tiles (fences only, rows 70–73)")
    print(format_dart_set("extTerrains", et_fences, 32))
    print()

    # ── ext_worksite (32×20) ──────────────────────────────────────────
    # All non-empty = barrier. Vehicles, fences, crates.
    ew = read_indices("ext_worksite")
    print(f"// ext_worksite: {len(ew)} barrier tiles out of {32*20}")
    print(format_dart_set("extWorksite", ew, 32))
    print()

    # ── ext_hotel_hospital (32×62) ────────────────────────────────────
    # All non-empty = barrier. Building facades.
    ehh = read_indices("ext_hotel_hospital")
    print(f"// ext_hotel_hospital: {len(ehh)} barrier tiles out of {32*62}")
    print(format_dart_set("extHotelHospital", ehh, 32))
    print()

    # ── ext_school (32×116) ───────────────────────────────────────────
    # All non-empty = barrier EXCEPT:
    #   - Basketball courts (rows 34–57): walkable surfaces
    #   - Soccer/football fields (rows 99–115): walkable surfaces
    es = read_indices("ext_school")
    court_rows = set(range(34, 58))  # rows 34–57
    field_rows = set(range(99, 116))  # rows 99–115
    es_filtered = filter_by_rows(es, 32, exclude_rows=court_rows | field_rows)
    excluded = len(es) - len(es_filtered)
    print(f"// ext_school: {len(es_filtered)} barrier tiles "
          f"(excluded {excluded} court/field tiles)")
    print(format_dart_set("extSchool", es_filtered, 32))
    print()

    # ── ext_office (32×95) ────────────────────────────────────────────
    # All non-empty = barrier. Building facades.
    eo = read_indices("ext_office")
    print(f"// ext_office: {len(eo)} barrier tiles out of {32*95}")
    print(format_dart_set("extOffice", eo, 32))


if __name__ == "__main__":
    main()
