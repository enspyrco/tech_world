#!/usr/bin/env python3
"""Extract LimeZu character parts into Tech World's sprite-sheet layout.

The game renders a character from a 512x64 sheet: sixteen 32x64 cells, being
twelve walk cells (four direction strips of three frames) followed by a
four-cell wave strip. See `player_component.dart:_buildAnimations`.

The LimeZu Character Generator ships each part as one big atlas of 32x64 cells
whose walk row holds *six* frames per direction. This script slices that row
down to our cadence and lays it out in our order, so the output is a normal
committed asset and the game never learns that a generator exists.

Run it when adding parts; commit the PNGs it writes. Nothing at build time or
run time depends on this file.

    python3 tool/extract_character_parts.py --list
    python3 tool/extract_character_parts.py

Requires Pillow (`pip3 install Pillow`) and the purchased LimeZu pack.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - developer tooling
    sys.exit("Pillow is required: pip3 install Pillow")

# ── The two layouts ────────────────────────────────────────────────────────

CELL_W, CELL_H = 32, 64

# Row index of the walk animation in the source atlas. Row 0 is four static
# poses, row 1 is idle, row 2 is walk. Verified by cropping and looking, not
# from documentation — the pack's Spritesheet_animations_GUIDE.png labels the
# rows but not their indices.
SOURCE_WALK_ROW = 2

# Frames per direction in the source, and the three we keep.
#
# The source cycle is neutral, contact, ..., contact — and the game's existing
# sprites use exactly neutral plus the two contact poses, which is frames
# 0, 1 and 4. Picking evenly (0, 2, 4) instead would give three near-neutral
# poses and the character would appear to glide.
SOURCE_FRAMES_PER_DIR = 6
KEEP_FRAMES = (0, 1, 4)

# Direction groups, in the order they appear in the source atlas. Established
# by comparing group 0 against a mirrored group 2: they differ by 8 pixels out
# of 2048, so those two are the side-facing pair, and the remaining two are
# distinguishable by eye (group 1 shows the back of the head).
SOURCE_DIR_ORDER = ("right", "up", "left", "down")

# Direction order in OUR sheet, from the texturePosition offsets in
# `_buildAnimations`: down at 0, left at 96, up at 192, right at 288.
OUTPUT_DIR_ORDER = ("down", "left", "up", "right")

OUTPUT_CELLS = 16
WAVE_CELLS = 4
SHEET_W, SHEET_H = OUTPUT_CELLS * CELL_W, CELL_H

DEFAULT_SOURCE = Path.home() / (
    "Library/CloudStorage/Dropbox/Work Files/AITW/tilesets/"
    "moderninteriors-win/2_Characters/Character_Generator"
)
DEFAULT_OUT = Path(__file__).resolve().parent.parent / "assets/images/parts"

# ── What to extract ────────────────────────────────────────────────────────
#
# A hand-picked starter set rather than all 1,248 files: every part shipped is
# an asset in the bundle and an enum value to maintain, so the set should grow
# deliberately. Source name -> the id the game knows it by.
#
# `Hairstyle_<style>_32x32_<colour>` — style is the shape, colour the palette.

# Ids mirror the source numbering (`hair_<style>_c<colour>`) rather than
# describing the art. An earlier pass named these by colour — `hair_01_black`,
# `hair_02_red` — from the filename numbering alone, and rendering them showed
# `hair_01_01` is ginger, `hair_02_06` is grey and `hair_05_05` is white.
# Almost none matched. A descriptive id is a claim about pixels nobody
# re-checks once it is an enum value and a UI label, so these stay
# source-faithful; human-facing names belong in the picker, chosen by someone
# looking at the art.
MANIFEST: dict[str, dict[str, str]] = {
    "body": {
        "Body_32x32_01": "body_01",
        "Body_32x32_03": "body_03",
        "Body_32x32_05": "body_05",
        "Body_32x32_07": "body_07",
        "Body_32x32_09": "body_09",
    },
    # Eyes are deliberately absent. The body sheets already carry a face, and
    # compositing Eyes_32x32_01 over Body_32x32_01 changes 8 pixels out of
    # 2048 — a subtle variant, not a required layer. Adding the slot later is
    # an enum plus a zPos between body and outfit; it is not needed to make a
    # character look finished.
    "hair": {
        "Hairstyle_01_32x32_01": "hair_01_c01",
        "Hairstyle_01_32x32_04": "hair_01_c04",
        "Hairstyle_02_32x32_02": "hair_02_c02",
        "Hairstyle_02_32x32_06": "hair_02_c06",
        "Hairstyle_03_32x32_01": "hair_03_c01",
        "Hairstyle_04_32x32_03": "hair_04_c03",
        "Hairstyle_05_32x32_05": "hair_05_c05",
        "Hairstyle_06_32x32_02": "hair_06_c02",
    },
    "outfit": {
        "Outfit_01_32x32_01": "outfit_01_c01",
        "Outfit_02_32x32_01": "outfit_02_c01",
        "Outfit_03_32x32_02": "outfit_03_c02",
        "Outfit_05_32x32_01": "outfit_05_c01",
        "Outfit_07_32x32_03": "outfit_07_c03",
        "Outfit_09_32x32_02": "outfit_09_c02",
    },
    "accessory": {
        "Accessory_03_Backpack_32x32_01": "accessory_backpack",
        "Accessory_15_Glasses_32x32_01": "accessory_glasses",
        "Accessory_04_Snapback_32x32_01": "accessory_snapback",
    },
}

# Which source directory each slot reads from.
SLOT_DIRS = {
    "body": "Bodies",
    "eyes": "Eyes",
    "hair": "Hairstyles",
    "outfit": "Outfits",
    "accessory": "Accessories",
}

SIZE_DIR = "32x32"  # the variant whose character cells are 32x64


def source_cell(atlas: Image.Image, col: int, row: int) -> Image.Image:
    box = (col * CELL_W, row * CELL_H, (col + 1) * CELL_W, (row + 1) * CELL_H)
    return atlas.crop(box)


def walk_frame(atlas: Image.Image, direction: str, frame: int) -> Image.Image:
    """One walk frame, addressed by direction rather than by column."""
    group = SOURCE_DIR_ORDER.index(direction)
    col = group * SOURCE_FRAMES_PER_DIR + frame
    return source_cell(atlas, col, SOURCE_WALK_ROW)


def build_sheet(atlas: Image.Image) -> Image.Image:
    if atlas.width < SOURCE_DIR_ORDER.__len__() * SOURCE_FRAMES_PER_DIR * CELL_W:
        raise ValueError(f"atlas too narrow for a full walk row: {atlas.size}")
    if atlas.height < (SOURCE_WALK_ROW + 1) * CELL_H:
        raise ValueError(f"atlas has no row {SOURCE_WALK_ROW}: {atlas.size}")

    sheet = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))

    cell = 0
    for direction in OUTPUT_DIR_ORDER:
        for frame in KEEP_FRAMES:
            sheet.paste(walk_frame(atlas, direction, frame),
                        (cell * CELL_W, 0))
            cell += 1

    # The wave strip has no source: the pack's animation set (idle, walk,
    # sleep, sit, phone, push cart, pick up, gift, lift, throw, hit, punch,
    # stab, grab gun, gun idle, shoot, hurt) contains no arms-raised greeting,
    # and the Exteriors addons only add parts, not animations.
    #
    # So every part's wave cells hold its neutral front-facing frame. A
    # composed character therefore stands still through a wave instead of
    # raising its arms — which is a missing animation, not a glitch. Leaving
    # these transparent would be the glitch: a waving player's hair, clothes
    # and face would vanish for the duration.
    neutral = walk_frame(atlas, "down", KEEP_FRAMES[0])
    for i in range(WAVE_CELLS):
        sheet.paste(neutral, ((OUTPUT_CELLS - WAVE_CELLS + i) * CELL_W, 0))

    return sheet


def extract(source: Path, out: Path, dry_run: bool = False) -> list[str]:
    written = []
    for slot, entries in MANIFEST.items():
        src_dir = source / SLOT_DIRS[slot] / SIZE_DIR
        if not src_dir.is_dir():
            raise SystemExit(f"missing source directory: {src_dir}")
        out_dir = out / slot
        out_dir.mkdir(parents=True, exist_ok=True)

        for src_name, part_id in entries.items():
            src_path = src_dir / f"{src_name}.png"
            if not src_path.is_file():
                raise SystemExit(f"missing part: {src_path}")

            with Image.open(src_path) as atlas:
                sheet = build_sheet(atlas.convert("RGBA"))

            # The renderer asserts this too, but failing here names the part.
            assert sheet.size == (SHEET_W, SHEET_H), sheet.size

            dest = out_dir / f"{part_id}.png"
            if not dry_run:
                sheet.save(dest)
            written.append(f"{slot}/{part_id}.png  <- {src_name}")
    return written


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", type=Path, default=DEFAULT_SOURCE,
                    help="LimeZu Character_Generator directory")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--list", action="store_true",
                    help="print what would be written, and write nothing")
    ap.add_argument("--manifest-json", action="store_true",
                    help="dump the manifest as JSON (for wiring the enums)")
    args = ap.parse_args()

    if args.manifest_json:
        print(json.dumps(MANIFEST, indent=2))
        return

    written = extract(args.source, args.out, dry_run=args.list)
    verb = "would write" if args.list else "wrote"
    for line in written:
        print(f"  {verb} {line}")
    print(f"{len(written)} parts, {SHEET_W}x{SHEET_H} each")


if __name__ == "__main__":
    main()
