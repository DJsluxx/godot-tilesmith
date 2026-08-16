@tool
extends RefCounted
##
## The builder. Turns a list of images into a TileSet.
##
## This is the single door every entry point goes through - the editor dock, the
## headless CLI and the test suite all call build(). Nothing here touches the
## editor, so the whole thing runs under `godot --headless`, which is what makes
## it testable at all.
##

const TSMMask := preload("res://addons/tilesmith/core/tsm_mask.gd")
const TSMOptions := preload("res://addons/tilesmith/core/tsm_options.gd")

const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "tga", "svg"]


## Every image file in a directory, sorted, so two runs over the same folder
## produce the same source order and therefore the same source ids.
static func collect_images(dir_path: String, recursive: bool = false) -> Array:
	var found: Array = []
	_collect_into(dir_path, recursive, found)
	found.sort()
	return found


static func _collect_into(dir_path: String, recursive: bool, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if recursive:
				_collect_into(full, true, out)
		elif IMAGE_EXTENSIONS.has(name.get_extension().to_lower()):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


## Load one image as {ok, texture, data, size, name, error}.
##
## Two paths on purpose. Inside the editor an image under res:// has a sibling
## .import file and load() returns the imported texture, whose resource_path the
## saved .tres can reference. Outside the editor (headless CLI, a folder that was
## never imported) there is no such file, so the bytes are read directly and
## wrapped in an ImageTexture - which works, but gets embedded in the .tres
## instead of referenced, so the caller is warned.
static func load_source(path: String) -> Dictionary:
	var result := {
		"ok": false, "texture": null, "data": PackedByteArray(),
		"size": Vector2i.ZERO, "name": path.get_file(), "error": "", "embedded": false,
	}
	var img: Image = null
	var tex: Texture2D = null

	if FileAccess.file_exists(path + ".import"):
		var res = load(path)
		if res is Texture2D:
			tex = res
			var src_img := tex.get_image()
			if src_img != null:
				img = Image.new()
				img.copy_from(src_img)
	if img == null:
		img = Image.new()
		var err := img.load(path)
		if err != OK:
			result.error = "Could not read '%s' as an image (error %d)." % [path, err]
			return result
		tex = ImageTexture.create_from_image(img)
		result.embedded = true

	if img.is_compressed():
		var derr := img.decompress()
		if derr != OK:
			result.error = "'%s' is a compressed texture that could not be decompressed; re-import it as lossless." % path
			return result
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	if img.get_width() <= 0 or img.get_height() <= 0:
		result.error = "'%s' has zero size." % path
		return result

	result.ok = true
	result.texture = tex
	result.data = img.get_data()
	result.size = Vector2i(img.get_width(), img.get_height())
	return result


## Build (or extend) a TileSet from already-loaded sources.
##
## sources: Array of dictionaries as returned by load_source().
## Returns {tileset, report, errors, warnings, masks}.
## `masks` is only populated when opts.terrain is true; the terrain module
## consumes it so that a mask is never computed twice.
static func build(sources: Array, opts: Dictionary, tileset: TileSet = null) -> Dictionary:
	var o := TSMOptions.normalize(opts)
	var errors: Array = TSMOptions.validate(o)
	var warnings: Array = []
	var report := {
		"sources": 0, "tiles_created": 0, "cells_skipped": 0,
		"collision_polygons": 0, "fallback_tiles": 0, "per_image": [],
	}
	var masks: Array = []

	if not errors.is_empty():
		return {"tileset": null, "report": report, "errors": errors,
			"warnings": warnings, "masks": masks}
	if sources.is_empty():
		errors.append("No images to build from.")
		return {"tileset": null, "report": report, "errors": errors,
			"warnings": warnings, "masks": masks}

	var tile_size: Vector2i = o.tile_size
	var ts := tileset if tileset != null else TileSet.new()
	ts.tile_size = tile_size

	var physics_layer := -1
	if o.collision_mode != "none":
		if ts.get_physics_layers_count() == 0:
			ts.add_physics_layer()
		physics_layer = 0

	for src_info in sources:
		if not src_info.get("ok", false):
			errors.append(str(src_info.get("error", "Unusable image source.")))
			continue
		if src_info.get("embedded", false):
			warnings.append("'%s' was read straight from disk, so its pixels are stored inside the TileSet instead of referencing the file. Import it into the project to reference it." % src_info.name)

		var image_size: Vector2i = src_info.size
		if image_size.x < tile_size.x or image_size.y < tile_size.y:
			warnings.append("'%s' is %dx%d, smaller than one %dx%d tile - skipped." % [
				src_info.name, image_size.x, image_size.y, tile_size.x, tile_size.y])
			continue

		var atlas := TileSetAtlasSource.new()
		atlas.texture = src_info.texture
		atlas.texture_region_size = tile_size
		atlas.margins = o.margins
		atlas.separation = o.separation
		atlas.resource_name = src_info.name.get_basename()

		# The source must join the TileSet BEFORE any tile is created: a
		# TileData only learns which physics/terrain layers exist through its
		# owning TileSet, so tiles created on a detached source silently get no
		# collision layer to write to.
		var source_id := ts.add_source(atlas)

		var grid: Vector2i = atlas.get_atlas_grid_size()
		var made := 0
		var skipped := 0
		var polys := 0
		var pending: Array = []

		for gy in grid.y:
			for gx in grid.x:
				var coords := Vector2i(gx, gy)
				var origin: Vector2i = o.margins + coords * (tile_size + o.separation)
				var empty_mask := TSMMask.cell_mask(
					src_info.data, image_size.x, origin, tile_size, o.empty_threshold)
				if TSMMask.mask_count(empty_mask) == 0:
					skipped += 1
					continue
				if atlas.get_tile_at_coords(coords) != Vector2i(-1, -1):
					continue
				atlas.create_tile(coords)
				made += 1
				var tile_data := atlas.get_tile_data(coords, 0)
				if physics_layer >= 0 and tile_data != null:
					var added := _apply_collision(
						tile_data, physics_layer, src_info.data, image_size, origin, tile_size, o)
					polys += added.count
					if added.fallback:
						report.fallback_tiles += 1
				if o.terrain:
					pending.append({"coords": coords, "origin": origin})

		if o.terrain:
			for p in pending:
				masks.append({
					"source_id": source_id, "coords": p.coords,
					"data": src_info.data, "image_width": image_size.x,
					"origin": p.origin, "tile_size": tile_size,
				})

		report.sources += 1
		report.tiles_created += made
		report.cells_skipped += skipped
		report.collision_polygons += polys
		report.per_image.append({
			"name": src_info.name, "source_id": source_id, "grid": grid,
			"tiles": made, "skipped": skipped, "polygons": polys,
		})

	if report.tiles_created == 0 and errors.is_empty():
		errors.append("Every cell was blank at the current settings. Check tile size (%dx%d) and empty_threshold (%s)." % [
			tile_size.x, tile_size.y, str(o.empty_threshold)])

	return {"tileset": ts, "report": report, "errors": errors,
		"warnings": warnings, "masks": masks}


## Writes the collision polygons for one tile. Returns {count, fallback}.
static func _apply_collision(tile_data: TileData, layer: int, data: PackedByteArray,
		image_size: Vector2i, origin: Vector2i, tile_size: Vector2i, o: Dictionary) -> Dictionary:
	var rects: Array = []
	var fallback := false

	match o.collision_mode:
		"full":
			rects = [Rect2i(0, 0, tile_size.x, tile_size.y)]
		"tight", "precise":
			var mask := TSMMask.cell_mask(
				data, image_size.x, origin, tile_size, o.collision_threshold)
			if TSMMask.mask_count(mask) == 0:
				# Visible at the blank threshold but not at the collision
				# threshold - a ghost tile. No shape rather than a wrong one.
				return {"count": 0, "fallback": false}
			if o.collision_mode == "tight":
				rects = [TSMMask.mask_bbox(mask, tile_size)]
			else:
				rects = TSMMask.decompose_rects(mask, tile_size, o.collision_min_area)
				if rects.is_empty():
					rects = [TSMMask.mask_bbox(mask, tile_size)]
					fallback = true
				elif rects.size() > o.collision_max_polygons:
					rects = [TSMMask.mask_bbox(mask, tile_size)]
					fallback = true

	var polygons := _rects_to_polygons(rects, tile_size)
	tile_data.set_collision_polygons_count(layer, polygons.size())
	for i in polygons.size():
		tile_data.set_collision_polygon_points(layer, i, polygons[i])
	return {"count": polygons.size(), "fallback": fallback}


## Rectangles in cell-local pixels -> polygons in Godot's tile space, whose
## origin is the CENTRE of the tile. Point order matches the one Godot's own
## tile collision editor produces for a default full-tile rectangle.
static func _rects_to_polygons(rects: Array, tile_size: Vector2i) -> Array:
	var half := Vector2(tile_size) * 0.5
	var out: Array = []
	for r in rects:
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		var x0 := float(r.position.x) - half.x
		var y0 := float(r.position.y) - half.y
		var x1 := float(r.position.x + r.size.x) - half.x
		var y1 := float(r.position.y + r.size.y) - half.y
		var p := PackedVector2Array()
		p.append(Vector2(x0, y0))
		p.append(Vector2(x1, y0))
		p.append(Vector2(x1, y1))
		p.append(Vector2(x0, y1))
		out.append(p)
	return out
