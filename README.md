# Tilesmith — batch TileSet builder for Godot 4

Point it at a folder of images. Get a finished `TileSet` resource with blank
cells skipped and collision shapes already baked.

Building a TileSet by hand in Godot 4 means adding an atlas source, setting the
region size, creating each tile, adding a physics layer, and then drawing a
collision polygon on every single tile. On a 100-tile sheet that is a few
hundred clicks before you have placed a single tile in your level. Tilesmith
does that pass for you and writes a `.tres` you can open, inspect and edit like
any other TileSet.

It is a plain Godot addon. No native code, no external dependency, no account,
no telemetry, no network access.

---

## Install

1. Copy the `addons/tilesmith` folder into your project's `addons/` folder.
2. **Project → Project Settings → Plugins →** enable **Tilesmith**.
3. The **Tilesmith** dock appears on the right.

Godot 4 is required. Built and tested on **Godot 4.7.1** (Windows).

---

## Use it

Set the source folder and the tile size, choose a collision shape, press
**Build TileSet**.

| Setting | What it does |
|---|---|
| **Images** | A folder of images, or a single image. Every image becomes one atlas source. |
| **Include sub-folders** | Walk the folder tree instead of just the top level. |
| **Tile size** | Size of one tile in pixels. Non-square is fine. |
| **Margins / Separation** | For sheets with a border or gaps between tiles. |
| **Blank if alpha under** | Cells with nothing this opaque in them do not become tiles at all. |
| **Collision** | `none`, `full`, `tight` or `precise` — see below. |
| **Ignore blobs under** | Drops stray antialiased specks so they never become collision shapes. |
| **Max shapes per tile** | Above this, a tile falls back to a single bounding box. |
| **Save to** | Where the `.tres` TileSet is written. |

Everything it did is printed in the dock: images read, tiles created, blank
cells skipped, collision shapes written, and any tile that had to fall back.

---

## The four collision modes

```
 artwork        none        full        tight       precise
 ┌────────┐   ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐
 │▓▓      │   │        │  │████████│  │████████│  │██      │
 │▓▓      │   │        │  │████████│  │████████│  │██      │
 │▓▓▓▓▓▓▓▓│   │        │  │████████│  │████████│  │████████│
 │▓▓▓▓▓▓▓▓│   │        │  │████████│  │████████│  │████████│
 └────────┘   └────────┘  └────────┘  └────────┘  └────────┘
                            1 shape     1 shape     2 shapes
```

- **none** — don't touch physics at all.
- **full** — one rectangle covering the whole tile. Right for solid terrain.
- **tight** — one rectangle around the artwork. Right for a platform that only
  fills part of its cell.
- **precise** — the artwork split into a small set of rectangles that cover the
  opaque pixels exactly.

### Why rectangles and not a traced outline

Godot requires tile collision polygons to be **convex**. Tracing the silhouette
of a sprite produces a concave polygon, which Godot cannot use correctly — the
usual result is collision that behaves in ways the shape does not explain.

So `precise` decomposes the opaque area into axis-aligned rectangles instead.
Rectangles are convex by construction, can never self-intersect, and the
decomposition covers exactly those pixels at or above the **Solid if alpha
over** threshold — no gaps, no overhang.

Two settings deliberately break that exactness and say so: a tile whose shapes
fall below **Ignore blobs under**, or which needs more than **Max shapes per
tile**, falls back to a single bounding box, and the dock reports every tile
that did. All three behaviours are asserted by the test suite, not assumed.

---

## Command line

Tilesmith Pro can rebuild a TileSet without opening the editor, so an artist
dropping a new sheet into the folder can be a build step rather than a chore:

```
godot --headless --path . \
      --script res://addons/tilesmith/pro/tsm_cli.gd -- \
      --input res://art/tiles --tile 16 --collision precise --terrain \
      --output res://art/tiles.tres
```

---

## What's in Pro

The free edition above is complete and unrestricted for what it does. **Tilesmith
Pro** adds the two things that turn it into a pipeline:

- **Terrain (autotile) seeding.** Godot needs a centre terrain plus up to eight
  peering bits on every tile — around 900 clicks on a 100-tile blob sheet.
  Tilesmith Pro reads them off the artwork: if a tile's right edge is solid, it
  connects to the right. It gives you a filled-in starting point to correct,
  instead of a blank grid to paint.
- **The headless command line** shown above, for build scripts and CI.

→ **[Get Tilesmith Pro — $9.99](https://salama62.gumroad.com/l/mtrgjm?utm_source=github&utm_medium=readme&utm_campaign=tilesmith-free)**

---

## Honest limits

Worth knowing before you install, not after:

- Built and tested on **Godot 4.7.1 on Windows**. It uses only ordinary
  `TileSet` API, but other versions and platforms are untested by us.
- **Square tiles.** Isometric and hexagonal tile shapes are not handled by the
  terrain seeder.
- **Terrain seeding is a seed, not a solver.** It reads edge opacity, which is
  right for ordinary blob and wang sheets and wrong for artwork whose edges do
  not describe its connectivity. It is meant to be corrected, and every bit it
  sets is editable in the normal terrain editor.
- **`precise` produces rectangles**, deliberately — see above. If you want one
  hand-drawn polygon per tile, draw it; Tilesmith is for the other 95 tiles.
- It **writes a new TileSet**. Point it at a new file rather than over one you
  have hand-edited, and keep your project in version control.
- Images are read through Godot's own importer. A texture imported with VRAM
  compression has lossy alpha, so import tilesheets as **Lossless**.

---

## Tests

The test suite lives in the [source repository](https://github.com/DJsluxx/godot-tilesmith)
and runs headless, with nothing to install:

```
godot --headless --path . --script res://tests/run_tests.gd
```

It generates its own fixture images, checks that those fixtures really contain
what they claim, and only then checks the builder against them — 89 assertions
in the free tree, 106 with the Pro modules present. They cover blank-cell
skipping, all four collision modes, exact coverage of the `precise`
decomposition, margins and separation, the min-area and max-shape fallbacks,
terrain bits, the editor dock, and a save/reload round trip.

---

MIT licensed. Not affiliated with or endorsed by the Godot Foundation.
