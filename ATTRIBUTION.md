# Third-party assets and attribution

Tech World's **source code** is licensed under the GNU AGPL v3.0 (see [`LICENSE`](LICENSE)).

**The art assets in `assets/` are not.** They are third-party works used under their own
licences, listed below. Enspyr Pty Ltd is not their copyright holder and does not, and cannot,
sublicense them under the AGPL. The AGPL in `LICENSE` covers the code Enspyr owns; the art is
carved out and governed solely by the terms in this file.

If you fork this repository, the code comes with you under the AGPL. **The art does not.**
Anyone shipping a build containing these assets needs their own licence from the original
authors — for the LimeZu packs, that means a purchase from
[limezu.itch.io](https://limezu.itch.io/).

---

## LimeZu — pixel art

Author: **LimeZu** ([limezu.itch.io](https://limezu.itch.io/)). Three separately-licensed
products are in use. The purchased packs and their licence documents live outside this
repository, in Nick's Dropbox under `Work Files/AITW/` (`tilesets/` and `tiled/limezu-tilesets/`).

| Product | Assets in this repo | Credits |
|---|---|---|
| [Modern Interiors](https://limezu.itch.io/moderninteriors) (full) | `assets/images/parts/**` — 22 character parts sliced from `2_Characters/Character_Generator` by `tool/extract_character_parts.py` | **Required** |
| [Modern Exteriors](https://limezu.itch.io/modernexteriors) | `assets/images/tilesets/ext_terrains.png`, `ext_office.png`, `ext_school.png`, `ext_hotel_hospital.png`, `ext_worksite.png` | **Required** |
| [Modern Office Revamped](https://limezu.itch.io/modernoffice) | `assets/images/tilesets/room_builder_office.png`, `assets/images/tilesets/modern_office.png`; `limezu_walls.png` (fetched at runtime, not bundled) | Appreciated |

### Licence terms, verbatim

**Modern Interiors** — `moderninteriors-win/LICENSE.txt`:

> MODERN INTERIORS FULL VERSION LICENSE
> YOU CAN:
> -Edit and use the asset in any commercial  or non commercial project
> -Use the asset in any commercial  or non commercial project
> YOU CAN'T:
> - Resell or distribute the asset to others
> - Edit and resell the asset to others
> - Credits required (limezu.itch.io)

**Modern Exteriors** — `modernexteriors-win/Modern_Exteriors_License.pdf`, signed, dated
2022-01-25. Note the third permission, which the other two licences do not spell out:

> YOU CAN:
> - Edit and use the asset in any commercial or non commercial project
> - Use the asset in any commercial or non commercial project
> - **Use the asset in open source projects (ex GitHub)**
> YOU CAN'T:
> - Resell or distribute the asset to others
> - Edit and resell the asset to others (including NFT minting)
> - Credits required (https://limezu.itch.io/)

**Modern Office Revamped** — `Modern_Office_Revamped_v1.2/LICENSE.txt`:

> MODERN OFFICE LICENSE
> YOU CAN:
> -Edit and use the asset in any commercial  or non commercial project
> -Use the asset in any commercial  or non commercial project
> YOU CAN'T:
> - Resell or distribute the asset to others
> - Edit and resell the asset to others
> - Credits are  appreciated

### Not used

`Modern tiles_Free` (the free Modern Interiors sampler) is also on disk and its licence forbids
commercial use. **Nothing in this repository is sourced from it**, and nothing should be.

---

## Unverified provenance

These ship in the repo with no traced source. Listed here so the gap is explicit rather than
implicit — resolving them is open work, not a settled matter.

| Asset | What is known |
|---|---|
| `assets/images/NPC11.png`, `NPC12.png`, `NPC13.png` | 512×64 character sheets, added 2024-07-01 in `21ca6704`. Not present in any LimeZu pack on disk. Their four-frame wave row has no counterpart in Modern Interiors' walk strip, so they are probably not from that pack. |
| `assets/images/single_room.png` | 1952×1920 composed room sheet. Not found by name in any owned pack; likely hand-assembled, source tiles unconfirmed. |
| `assets/images/claude_bot.png`, `gremlin_bot.png`, `dreamfinder_bot.png`, `dreamfinder_bot_sheet.png` | Bot sprites; believed project-original, not confirmed. |

---

## Software dependencies

Flutter (BSD-3-Clause), Flame (MIT), LiveKit (Apache-2.0), Firebase (Apache-2.0 / BSD) — all
permissive. See [`docs/licensing.html`](docs/licensing.html) for the full licensing position.
