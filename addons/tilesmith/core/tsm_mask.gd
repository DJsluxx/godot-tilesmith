@tool
extends RefCounted
##
## Alpha-mask utilities.
##
## Everything here operates on a raw RGBA8 byte buffer plus an image width, so a
## whole tilesheet is read once and then indexed, instead of paying for a
## get_pixel() call per pixel.
##
## The important design decision lives in decompose_rects(): Godot requires tile
## collision polygons to be CONVEX. Tracing the outline of a sprite produces
## concave polygons, so this module decomposes the opaque area of a cell into a
## small set of axis-aligned rectangles instead. Rectangles are convex by
## construction and can never self-intersect.
##

## Alpha of one pixel, 0.0 - 1.0. Out-of-bounds reads as fully transparent.
static func alpha_at(data: PackedByteArray, image_width: int, x: int, y: int) -> float:
	if x < 0 or y < 0 or image_width <= 0:
		return 0.0
	var idx := (y * image_width + x) * 4 + 3
	if idx < 0 or idx >= data.size():
		return 0.0
	return float(data[idx]) / 255.0


## Boolean mask of one cell: 1 where alpha >= threshold, else 0. Row-major, w*h.
static func cell_mask(data: PackedByteArray, image_width: int, origin: Vector2i,
		size: Vector2i, threshold: float) -> PackedByteArray:
	var out := PackedByteArray()
	if size.x <= 0 or size.y <= 0:
		return out
	out.resize(size.x * size.y)
	for y in size.y:
		var row := y * size.x
		var sy := origin.y + y
		for x in size.x:
			out[row + x] = 1 if alpha_at(data, image_width, origin.x + x, sy) >= threshold else 0
	return out


## How many pixels in the mask are set.
static func mask_count(mask: PackedByteArray) -> int:
	var n := 0
	for v in mask:
		if v != 0:
			n += 1
	return n


## Tight bounding box of the set pixels. Returns a zero-size Rect2i when empty.
static func mask_bbox(mask: PackedByteArray, size: Vector2i) -> Rect2i:
	var min_x := size.x
	var min_y := size.y
	var max_x := -1
	var max_y := -1
	for y in size.y:
		var row := y * size.x
		for x in size.x:
			if mask[row + x] != 0:
				if x < min_x: min_x = x
				if x > max_x: max_x = x
				if y < min_y: min_y = y
				if y > max_y: max_y = y
	if max_x < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## Fraction (0.0 - 1.0) of the given sub-rectangle of the mask that is set.
## Used to decide whether a tile edge is "solid" when seeding terrain bits.
static func region_fill(mask: PackedByteArray, size: Vector2i, region: Rect2i) -> float:
	var x0: int = max(0, region.position.x)
	var y0: int = max(0, region.position.y)
	var x1: int = min(size.x, region.position.x + region.size.x)
	var y1: int = min(size.y, region.position.y + region.size.y)
	if x1 <= x0 or y1 <= y0:
		return 0.0
	var hit := 0
	for y in range(y0, y1):
		var row := y * size.x
		for x in range(x0, x1):
			if mask[row + x] != 0:
				hit += 1
	return float(hit) / float((x1 - x0) * (y1 - y0))


## Decompose the set pixels into axis-aligned rectangles.
##
## Scans row by row, finds horizontal runs, and extends a run downward for as
## long as the row below has an identical run. The result covers exactly the set
## pixels - no more, no less - which is what makes the coverage assertion in the
## test suite meaningful.
##
## min_area drops specks (stray antialiased pixels) that would otherwise become
## degenerate collision shapes.
static func decompose_rects(mask: PackedByteArray, size: Vector2i, min_area: int) -> Array:
	var out: Array = []
	if size.x <= 0 or size.y <= 0:
		return out
	# open[i] = {x0, x1, y0} for runs still being extended downward.
	var open: Array = []
	for y in size.y + 1:
		var runs: Array = []
		if y < size.y:
			var row := y * size.x
			var x := 0
			while x < size.x:
				if mask[row + x] != 0:
					var start := x
					while x < size.x and mask[row + x] != 0:
						x += 1
					runs.append(Vector2i(start, x))
				else:
					x += 1
		# Match open runs against this row's runs by exact [x0, x1) equality.
		var still_open: Array = []
		var consumed := {}
		for o in open:
			var matched := -1
			for i in runs.size():
				if consumed.has(i):
					continue
				if runs[i].x == o.x0 and runs[i].y == o.x1:
					matched = i
					break
			if matched >= 0:
				consumed[matched] = true
				still_open.append(o)
			else:
				out.append(Rect2i(o.x0, o.y0, o.x1 - o.x0, y - o.y0))
		for i in runs.size():
			if not consumed.has(i):
				still_open.append({"x0": runs[i].x, "x1": runs[i].y, "y0": y})
		open = still_open

	var kept: Array = []
	for r in out:
		if r.size.x * r.size.y >= min_area:
			kept.append(r)
	kept.sort_custom(func(a, b):
		if a.position.y != b.position.y:
			return a.position.y < b.position.y
		return a.position.x < b.position.x)
	return kept
