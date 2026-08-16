@tool
extends RefCounted
##
## Test fixtures, generated rather than committed as binaries, so every expected
## number in the suite can be derived from the code that drew the pixels.
##

const OPAQUE := Color(0.2, 0.6, 0.9, 1.0)
const CLEAR := Color(0, 0, 0, 0)

const GEN_DIR := "res://tests/_gen"

## Cell layout of shapes.png, row-major, 4x4 cells of 16x16.
const SHAPES_LAYOUT := [
	"full", "blank", "bottom_half", "l_shape",
	"speck", "no_top", "blank", "full",
	"blank", "blank", "blank", "blank",
	"full", "blank", "blank", "checker",
]
const SHAPES_TILE := 16
const SHAPES_COLS := 4
const SHAPES_ROWS := 4

## Opaque pixel counts per shape, at 16x16. Hand-derived from _draw_cell below;
## the suite cross-checks these against the mask, so a drift in either fails.
const SHAPE_AREA := {
	"full": 256,
	"blank": 0,
	"bottom_half": 128,
	"l_shape": 192,
	"speck": 1,
	"no_top": 208,
	"checker": 128,
}


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GEN_DIR))


## 64x64 sheet, 4x4 cells of 16px. Returns the absolute file path.
static func shapes_png() -> String:
	ensure_dir()
	var img := Image.create(SHAPES_COLS * SHAPES_TILE, SHAPES_ROWS * SHAPES_TILE,
		false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	for i in SHAPES_LAYOUT.size():
		var cx := i % SHAPES_COLS
		var cy := i / SHAPES_COLS
		_draw_cell(img, Vector2i(cx * SHAPES_TILE, cy * SHAPES_TILE),
			SHAPES_TILE, SHAPES_LAYOUT[i])
	var path := GEN_DIR.path_join("shapes.png")
	img.save_png(path)
	return path


## 19x19 sheet: margins 2, separation 1, tile 8 -> a 2x2 grid.
## Only cells (0,0) and (1,1) carry pixels.
static func spaced_png() -> String:
	ensure_dir()
	var img := Image.create(19, 19, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	for p in [Vector2i(2, 2), Vector2i(11, 11)]:
		for y in 8:
			for x in 8:
				img.set_pixel(p.x + x, p.y + y, OPAQUE)
	var path := GEN_DIR.path_join("spaced.png")
	img.save_png(path)
	return path


## An image smaller than one tile, to exercise the skip-and-warn branch.
static func tiny_png() -> String:
	ensure_dir()
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(OPAQUE)
	var path := GEN_DIR.path_join("tiny.png")
	img.save_png(path)
	return path


static func _draw_cell(img: Image, origin: Vector2i, size: int, kind: String) -> void:
	match kind:
		"blank":
			pass
		"full":
			_rect(img, origin, Rect2i(0, 0, size, size))
		"bottom_half":
			_rect(img, origin, Rect2i(0, size / 2, size, size / 2))
		"l_shape":
			# Rows 0..7 are half width, rows 8..15 are full width.
			# Row-run merging must find exactly two rectangles here.
			_rect(img, origin, Rect2i(0, 0, size / 2, size / 2))
			_rect(img, origin, Rect2i(0, size / 2, size, size / 2))
		"speck":
			_rect(img, origin, Rect2i(0, 0, 1, 1))
		"no_top":
			# Solid except the top 3 rows: the terrain seeder must connect on
			# every side except the top.
			_rect(img, origin, Rect2i(0, 3, size, size - 3))
		"checker":
			# 4x4 blocks in a checkerboard: eight rectangles, half the area.
			var block := 4
			var n := size / block
			for by in n:
				for bx in n:
					if (bx + by) % 2 == 0:
						_rect(img, origin, Rect2i(bx * block, by * block, block, block))


static func _rect(img: Image, origin: Vector2i, r: Rect2i) -> void:
	for y in r.size.y:
		for x in r.size.x:
			img.set_pixel(origin.x + r.position.x + x, origin.y + r.position.y + y, OPAQUE)
