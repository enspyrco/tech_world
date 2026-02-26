#!/usr/bin/env python3
"""One-time code generation: scan tileset PNGs for non-empty tiles.

For each tileset, checks every 32x32 cell for any pixel with alpha > 0.
Outputs:
  - Per-row summary showing which tiles are non-empty
  - Dart `Set<int>` literal ready to paste into predefined_tilesets.dart

Usage:
    python3 tool/generate_barrier_indices.py
"""

import os
from pathlib import Path
from PIL import Image

# Project root (script lives in tool/).
ROOT = Path(__file__).resolve().parent.parent
TILESETS_DIR = ROOT / "assets" / "images" / "tilesets"

TILE_SIZE = 32

# Tilesets to scan — (filename, id, columns, rows).
TILESETS = [
    ("modern_office.png", "modern_office", 16, 53),
    ("ext_terrains.png", "ext_terrains", 32, 74),
    ("ext_worksite.png", "ext_worksite", 32, 20),
    ("ext_hotel_hospital.png", "ext_hotel_hospital", 32, 62),
    ("ext_school.png", "ext_school", 32, 116),
    ("ext_office.png", "ext_office", 32, 95),
]


def scan_tileset(path: Path, columns: int, rows: int) -> list[int]:
    """Return indices of tiles that have at least one pixel with alpha > 0."""
    img = Image.open(path).convert("RGBA")
    non_empty: list[int] = []

    for row in range(rows):
        for col in range(columns):
            x0 = col * TILE_SIZE
            y0 = row * TILE_SIZE
            tile = img.crop((x0, y0, x0 + TILE_SIZE, y0 + TILE_SIZE))

            # Check if any pixel has alpha > 0.
            alpha = tile.split()[3]  # A channel
            if alpha.getbbox() is not None:
                non_empty.append(row * columns + col)

    return non_empty


def format_row_summary(indices: list[int], columns: int, rows: int) -> str:
    """Per-row summary: row number, count, and range of non-empty tiles."""
    index_set = set(indices)
    lines: list[str] = []
    for row in range(rows):
        row_start = row * columns
        row_indices = [i for i in range(row_start, row_start + columns) if i in index_set]
        if row_indices:
            cols = [i - row_start for i in row_indices]
            lines.append(
                f"  // Row {row:3d}: {len(row_indices):2d}/{columns} non-empty "
                f"(cols {cols[0]}–{cols[-1]})"
            )
        else:
            lines.append(f"  // Row {row:3d}:  0/{columns} (empty)")
    return "\n".join(lines)


def find_contiguous_ranges(indices: list[int]) -> list[tuple[int, int]]:
    """Group sorted indices into contiguous (start, end) ranges."""
    if not indices:
        return []
    ranges: list[tuple[int, int]] = []
    start = indices[0]
    end = indices[0]
    for i in indices[1:]:
        if i == end + 1:
            end = i
        else:
            ranges.append((start, end))
            start = i
            end = i
    ranges.append((start, end))
    return ranges


def format_dart_set(name: str, indices: list[int], columns: int, rows: int) -> str:
    """Format as a Dart Set<int> using range-based for loops where possible."""
    lines: list[str] = []
    lines.append(f"final Set<int> _{name}Barriers = {{")

    ranges = find_contiguous_ranges(indices)
    for start, end in ranges:
        count = end - start + 1
        start_row = start // columns
        end_row = end // columns
        if count >= 8:
            # Use a for loop for large contiguous ranges.
            lines.append(
                f"  for (int i = {start}; i <= {end}; i++) i, "
                f"// rows {start_row}–{end_row} ({count} tiles)"
            )
        else:
            # Inline small ranges.
            vals = ", ".join(str(i) for i in range(start, end + 1))
            lines.append(f"  {vals}, // row {start_row}")

    lines.append("};")
    return "\n".join(lines)


def main() -> None:
    print("=" * 72)
    print("Tileset Barrier Index Scanner")
    print("=" * 72)

    for filename, tileset_id, columns, rows in TILESETS:
        path = TILESETS_DIR / filename
        if not path.exists():
            print(f"\n⚠ MISSING: {path}")
            continue

        print(f"\n{'─' * 72}")
        print(f"Tileset: {tileset_id} ({columns}×{rows} = {columns * rows} tiles)")
        print(f"File:    {filename}")
        print(f"{'─' * 72}")

        indices = scan_tileset(path, columns, rows)

        total = columns * rows
        print(f"\nNon-empty tiles: {len(indices)} / {total} "
              f"({100 * len(indices) / total:.1f}%)")

        print(f"\n--- Row-by-row summary ---")
        print(format_row_summary(indices, columns, rows))

        print(f"\n--- Dart Set<int> ---")
        print(format_dart_set(tileset_id, indices, columns, rows))

        # Also write raw indices to a file for easy reference.
        out_path = ROOT / "tool" / f"{tileset_id}_indices.txt"
        with open(out_path, "w") as f:
            f.write(f"# {tileset_id}: non-empty tile indices ({len(indices)}/{total})\n")
            f.write(f"# {columns} columns × {rows} rows\n\n")
            for row in range(rows):
                row_start = row * columns
                row_indices = [i for i in indices if row_start <= i < row_start + columns]
                if row_indices:
                    f.write(f"Row {row:3d}: {row_indices}\n")
            f.write(f"\nAll indices: {indices}\n")

        print(f"  (raw indices saved to tool/{tileset_id}_indices.txt)")


if __name__ == "__main__":
    main()
