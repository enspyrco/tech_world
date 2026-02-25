#!/usr/bin/env python3
"""Refine modern_office barriers using vertical-run detection.

Multi-cell-tall objects (bookshelves, partitions, plants) have their top tiles
incorrectly tagged as barriers. In a top-down game the player walks *behind*
the top — only the bottom/base tile should block movement.

Algorithm:
  For each column of the 16×53 tileset, find vertical runs of consecutive
  non-empty tiles. For each run:
    - Length 1 (single-cell object): keep as barrier
    - Length >= 2 (multi-cell object): only the bottom tile is a barrier;
      the top N-1 tiles are excluded

Usage:
    python3 tool/refine_modern_office_barriers.py           # normal run
    python3 tool/refine_modern_office_barriers.py --verify  # run integrity checks
    python3 tool/refine_modern_office_barriers.py --dart    # output Dart Set<int>
"""

import argparse
import sys
from pathlib import Path

from PIL import Image

# Project root (script lives in tool/).
ROOT = Path(__file__).resolve().parent.parent
TILESETS_DIR = ROOT / "assets" / "images" / "tilesets"

COLUMNS = 16
ROWS = 53
TILE_SIZE = 32
TOTAL_TILES = COLUMNS * ROWS  # 848


def build_occupancy_grid(path: Path) -> list[list[bool]]:
    """Build a ROWS×COLUMNS occupancy grid (True = non-empty tile)."""
    img = Image.open(path).convert("RGBA")
    grid: list[list[bool]] = []

    for row in range(ROWS):
        row_data: list[bool] = []
        for col in range(COLUMNS):
            x0 = col * TILE_SIZE
            y0 = row * TILE_SIZE
            tile = img.crop((x0, y0, x0 + TILE_SIZE, y0 + TILE_SIZE))
            alpha = tile.split()[3]
            row_data.append(alpha.getbbox() is not None)
        grid.append(row_data)

    return grid


def find_vertical_runs(grid: list[list[bool]]) -> list[list[tuple[int, int]]]:
    """For each column, find vertical runs of consecutive non-empty tiles.

    Returns a list (one per column) of (start_row, length) tuples.
    """
    all_runs: list[list[tuple[int, int]]] = []

    for col in range(COLUMNS):
        runs: list[tuple[int, int]] = []
        run_start: int | None = None

        for row in range(ROWS):
            if grid[row][col]:
                if run_start is None:
                    run_start = row
            else:
                if run_start is not None:
                    runs.append((run_start, row - run_start))
                    run_start = None

        # Close any run that reaches the bottom.
        if run_start is not None:
            runs.append((run_start, ROWS - run_start))

        all_runs.append(runs)

    return all_runs


def compute_barrier_and_excluded(
    grid: list[list[bool]],
    runs_per_col: list[list[tuple[int, int]]],
) -> tuple[set[int], set[int]]:
    """Compute barrier and excluded tile index sets from vertical runs.

    For each run:
      - Length 1: the single tile is a barrier
      - Length >= 2: the bottom tile is a barrier; the top N-1 tiles are excluded
    """
    barriers: set[int] = set()
    excluded: set[int] = set()

    for col, runs in enumerate(runs_per_col):
        for start_row, length in runs:
            if length == 1:
                barriers.add(start_row * COLUMNS + col)
            else:
                # Bottom tile of the run is the barrier.
                bottom_row = start_row + length - 1
                barriers.add(bottom_row * COLUMNS + col)
                # Top N-1 tiles are excluded.
                for row in range(start_row, start_row + length - 1):
                    excluded.add(row * COLUMNS + col)

    return barriers, excluded


def annotated_grid(
    grid: list[list[bool]],
    barriers: set[int],
    excluded: set[int],
) -> str:
    """Render an annotated grid visualization.

    Legend:
      B = barrier (bottom of run, or single-cell)
      x = excluded (top of multi-cell run)
      . = empty (transparent)
    """
    lines: list[str] = []
    lines.append(f"     {''.join(f'{c:>2}' for c in range(COLUMNS))}")
    lines.append(f"     {'--' * COLUMNS}")

    for row in range(ROWS):
        cells: list[str] = []
        for col in range(COLUMNS):
            idx = row * COLUMNS + col
            if idx in barriers:
                cells.append(" B")
            elif idx in excluded:
                cells.append(" x")
            elif grid[row][col]:
                # Non-empty but not categorized — shouldn't happen.
                cells.append(" ?")
            else:
                cells.append(" .")
        lines.append(f"R{row:>3} {''.join(cells)}")

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


def format_dart_set(barriers: set[int]) -> str:
    """Format barriers as Dart Set<int> for predefined_tilesets.dart."""
    sorted_indices = sorted(barriers)
    lines: list[str] = []
    lines.append("final Set<int> _modernOfficeBarriers = {")

    ranges = find_contiguous_ranges(sorted_indices)
    for start, end in ranges:
        count = end - start + 1
        start_row = start // COLUMNS
        end_row = end // COLUMNS
        if count >= 8:
            lines.append(
                f"  for (int i = {start}; i <= {end}; i++) i, "
                f"// rows {start_row}–{end_row} ({count} tiles)"
            )
        else:
            vals = ", ".join(str(i) for i in range(start, end + 1))
            lines.append(f"  {vals}, // row {start_row}")
    lines.append("};")
    return "\n".join(lines)


def verify(
    grid: list[list[bool]],
    barriers: set[int],
    excluded: set[int],
) -> bool:
    """Run integrity checks. Returns True if all pass."""
    all_non_empty = {
        row * COLUMNS + col
        for row in range(ROWS)
        for col in range(COLUMNS)
        if grid[row][col]
    }

    ok = True

    # Check 1: barrier + excluded = all non-empty tiles.
    union = barriers | excluded
    if union != all_non_empty:
        missing = all_non_empty - union
        extra = union - all_non_empty
        if missing:
            print(f"FAIL: {len(missing)} non-empty tiles not categorized: {sorted(missing)}")
        if extra:
            print(f"FAIL: {len(extra)} empty tiles incorrectly categorized: {sorted(extra)}")
        ok = False
    else:
        print("PASS: barrier + excluded = all non-empty tiles")

    # Check 2: no overlap between barriers and excluded.
    overlap = barriers & excluded
    if overlap:
        print(f"FAIL: {len(overlap)} tiles in both sets: {sorted(overlap)}")
        ok = False
    else:
        print("PASS: no overlap between barriers and excluded")

    # Check 3: every excluded tile has a non-empty tile below it in its column.
    bad_excluded: list[int] = []
    for idx in sorted(excluded):
        row = idx // COLUMNS
        col = idx % COLUMNS
        # Check that there is a non-empty tile somewhere below in the same column.
        has_below = False
        for r in range(row + 1, ROWS):
            if grid[r][col]:
                has_below = True
                break
        if not has_below:
            bad_excluded.append(idx)
    if bad_excluded:
        print(f"FAIL: {len(bad_excluded)} excluded tiles have nothing below them: {bad_excluded}")
        ok = False
    else:
        print("PASS: every excluded tile has a non-empty tile below it")

    # Check 4: every barrier tile in a multi-cell run is actually the bottom
    # of its column run.
    bad_barriers: list[int] = []
    for idx in sorted(barriers):
        row = idx // COLUMNS
        col = idx % COLUMNS
        # If there is a non-empty tile directly below, this isn't the bottom.
        if row + 1 < ROWS and grid[row + 1][col]:
            bad_barriers.append(idx)
    if bad_barriers:
        print(f"FAIL: {len(bad_barriers)} barriers are not at bottom of their run: {bad_barriers}")
        ok = False
    else:
        print("PASS: every barrier is at the bottom of its vertical run")

    return ok


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true", help="Run integrity checks")
    parser.add_argument("--dart", action="store_true", help="Output Dart Set<int>")
    args = parser.parse_args()

    path = TILESETS_DIR / "modern_office.png"
    if not path.exists():
        print(f"ERROR: {path} not found")
        sys.exit(1)

    print("Loading modern_office.png...")
    grid = build_occupancy_grid(path)

    all_non_empty = sum(1 for row in grid for cell in row if cell)
    print(f"Non-empty tiles: {all_non_empty} / {TOTAL_TILES}")

    print("\nDetecting vertical runs...")
    runs_per_col = find_vertical_runs(grid)

    # Print run summary per column.
    total_runs = sum(len(runs) for runs in runs_per_col)
    multi_cell_runs = sum(1 for runs in runs_per_col for _, length in runs if length >= 2)
    single_cell_runs = total_runs - multi_cell_runs
    print(f"Total runs: {total_runs} ({single_cell_runs} single-cell, {multi_cell_runs} multi-cell)")

    barriers, excluded = compute_barrier_and_excluded(grid, runs_per_col)
    print(f"\nBarrier tiles:  {len(barriers)} (was {all_non_empty})")
    print(f"Excluded tiles: {len(excluded)}")
    print(f"Reduction:      {all_non_empty} → {len(barriers)} "
          f"({all_non_empty - len(barriers)} tiles excluded)")

    # Print the annotated grid.
    print(f"\n{'=' * 60}")
    print("Annotated grid (B=barrier, x=excluded, .=empty)")
    print(f"{'=' * 60}")
    print(annotated_grid(grid, barriers, excluded))

    if args.verify:
        print(f"\n{'=' * 60}")
        print("Verification")
        print(f"{'=' * 60}")
        ok = verify(grid, barriers, excluded)
        if not ok:
            sys.exit(1)
        print("\nAll checks passed!")

    if args.dart:
        print(f"\n{'=' * 60}")
        print("Dart Set<int>")
        print(f"{'=' * 60}")
        print(format_dart_set(barriers))

    # Always write the barrier indices to a file.
    out_path = ROOT / "tool" / "modern_office_refined_barriers.txt"
    sorted_barriers = sorted(barriers)
    sorted_excluded = sorted(excluded)
    with open(out_path, "w") as f:
        f.write(f"# modern_office refined barriers\n")
        f.write(f"# Vertical-run detection: only bottom tiles of multi-cell objects\n")
        f.write(f"# Original: {all_non_empty} barriers → Refined: {len(barriers)} barriers\n")
        f.write(f"# Excluded: {len(excluded)} top tiles of multi-cell objects\n\n")
        f.write(f"Barrier indices ({len(barriers)}):\n{sorted_barriers}\n\n")
        f.write(f"Excluded indices ({len(excluded)}):\n{sorted_excluded}\n")
    print(f"\nResults saved to tool/modern_office_refined_barriers.txt")


if __name__ == "__main__":
    main()
