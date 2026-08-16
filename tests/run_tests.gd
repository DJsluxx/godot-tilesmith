extends SceneTree
##
## Tilesmith test suite. Runs headless:
##
##   godot --headless --path ship/tilesmith/src --script res://tests/run_tests.gd
##
## Exits 0 when every check passes, 1 otherwise.
##
## The suite loads the SHIPPED scripts from res://addons/tilesmith/ - the same
## bytes build.py packages into the zip - so a pass is a pass on what the buyer
## installs, not on a copy.
##

const TSMBuild := preload("res://addons/tilesmith/core/tsm_build.gd")
const TSMMask := preload("res://addons/tilesmith/core/tsm_mask.gd")
const TSMOptions := preload("res://addons/tilesmith/core/tsm_options.gd")
const Fixtures := preload("res://tests/make_fixtures.gd")
const PRO_TERRAIN_PATH := "res://addons/tilesmith/pro/tsm_terrain.gd"

## Loaded at runtime, not preloaded: the free edition ships without pro/, and a
## preload of a missing path is a compile error that would stop the whole suite
## from running in the very tree it most needs to check.
var TSMTerrain = load(PRO_TERRAIN_PATH) if ResourceLoader.exists(PRO_TERRAIN_PATH) else null

var _passed := 0
var _failed := 0
var _current := ""


func _initialize() -> void:
	print("Tilesmith test suite - Godot %s" % Engine.get_version_info().string)
	print("")

	var shapes_path := Fixtures.shapes_png()
	var spaced_path := Fixtures.spaced_png()
	var tiny_path := Fixtures.tiny_png()

	test_fixtures_match_their_declared_areas(shapes_path)
	test_options_validation()
	test_empty_input()
	test_tile_and_blank_counts(shapes_path)
	test_no_collision_layer_by_default(shapes_path)
	test_full_collision(shapes_path)
	test_tight_collision(shapes_path)
	test_precise_collision_covers_exactly(shapes_path)
	test_precise_min_area_fallback(shapes_path)
	test_max_polygons_fallback(shapes_path)
	test_margins_and_separation(spaced_path)
	test_image_smaller_than_tile(tiny_path)
	test_terrain_seeding(shapes_path)
	test_save_and_reload_round_trip(shapes_path)
	test_dock_constructs_and_reads_back(shapes_path)

	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


# ---------------------------------------------------------------- assertions

func _case(name: String) -> void:
	_current = name


func _ok(condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL  %s: %s" % [_current, detail])


func _eq(actual, expected, what: String) -> void:
	_ok(actual == expected, "%s - expected %s, got %s" % [what, str(expected), str(actual)])


# ------------------------------------------------------------------- helpers

func _load(path: String) -> Array:
	var s := TSMBuild.load_source(path)
	_ok(s.ok, "could not load fixture %s: %s" % [path, s.error])
	return [s]


func _shape_coords(kind: String) -> Vector2i:
	var i: int = Fixtures.SHAPES_LAYOUT.find(kind)
	return Vector2i(i % Fixtures.SHAPES_COLS, i / Fixtures.SHAPES_COLS)


func _first_atlas(ts: TileSet) -> TileSetAtlasSource:
	return ts.get_source(ts.get_source_id(0)) as TileSetAtlasSource


func _polygons(ts: TileSet, coords: Vector2i) -> Array:
	var td := _first_atlas(ts).get_tile_data(coords, 0)
	var out: Array = []
	for i in td.get_collision_polygons_count(0):
		out.append(td.get_collision_polygon_points(0, i))
	return out


## Area of an axis-aligned rectangle polygon, in pixels.
func _poly_area(p: PackedVector2Array) -> float:
	var r := Rect2(p[0], Vector2.ZERO)
	for pt in p:
		r = r.expand(pt)
	return r.size.x * r.size.y


# --------------------------------------------------------------------- tests

## The suite's expected numbers are only meaningful if the fixture really
## contains what it says it does. Check the pixels before checking the builder -
## a test case must be proven internally coherent before its failure is blamed
## on the code.
func test_fixtures_match_their_declared_areas(path: String) -> void:
	_case("fixtures match their declared areas")
	var s := TSMBuild.load_source(path)
	if not s.ok:
		_ok(false, s.error)
		return
	for i in Fixtures.SHAPES_LAYOUT.size():
		var kind: String = Fixtures.SHAPES_LAYOUT[i]
		var origin := Vector2i(
			(i % Fixtures.SHAPES_COLS) * Fixtures.SHAPES_TILE,
			(i / Fixtures.SHAPES_COLS) * Fixtures.SHAPES_TILE)
		var mask := TSMMask.cell_mask(s.data, s.size.x, origin,
			Vector2i(Fixtures.SHAPES_TILE, Fixtures.SHAPES_TILE), 0.5)
		_eq(TSMMask.mask_count(mask), Fixtures.SHAPE_AREA[kind],
			"opaque pixels in '%s' cell" % kind)


func test_options_validation() -> void:
	_case("options validation")
	_eq(TSMOptions.validate(TSMOptions.normalize({})).size(), 0, "defaults are valid")
	_ok(TSMOptions.validate(TSMOptions.normalize({"tile_size": Vector2i(0, 16)})).size() > 0,
		"zero tile width must be rejected")
	_ok(TSMOptions.validate(TSMOptions.normalize({"collision_mode": "outline"})).size() > 0,
		"unknown collision mode must be rejected")
	_ok(TSMOptions.validate(TSMOptions.normalize({"empty_threshold": 1.5})).size() > 0,
		"threshold above 1.0 must be rejected")
	_ok(TSMOptions.validate(TSMOptions.normalize({"terrain_band": 99})).size() > 0,
		"band larger than the tile must be rejected")
	_ok(TSMOptions.validate(TSMOptions.normalize({"margins": Vector2i(-1, 0)})).size() > 0,
		"negative margins must be rejected")
	# Bad options must never produce a half-built TileSet.
	var bad := TSMBuild.build([], {"tile_size": Vector2i(0, 0)})
	_ok(bad.errors.size() > 0, "invalid options report an error")
	_eq(bad.tileset, null, "invalid options return no TileSet")


func test_empty_input() -> void:
	_case("empty input")
	var r := TSMBuild.build([], {"tile_size": Vector2i(16, 16)})
	_ok(r.errors.size() > 0, "no images reports an error")
	_eq(r.report.tiles_created, 0, "no tiles created")


func test_tile_and_blank_counts(path: String) -> void:
	_case("tile and blank counts")
	var expected_tiles := 0
	for kind in Fixtures.SHAPES_LAYOUT:
		if Fixtures.SHAPE_AREA[kind] > 0:
			expected_tiles += 1
	var r := TSMBuild.build(_load(path), {"tile_size": Vector2i(16, 16)})
	_eq(r.errors.size(), 0, "build errors")
	_eq(r.report.tiles_created, expected_tiles, "tiles created")
	_eq(r.report.cells_skipped, 16 - expected_tiles, "blank cells skipped")
	_eq(_first_atlas(r.tileset).get_tiles_count(), expected_tiles, "tiles in the atlas source")
	# A blank cell must not exist as a tile at all.
	_eq(_first_atlas(r.tileset).get_tile_at_coords(_shape_coords("blank")), Vector2i(-1, -1),
		"blank cell has no tile")


func test_no_collision_layer_by_default(path: String) -> void:
	_case("no physics layer unless asked")
	var r := TSMBuild.build(_load(path), {"tile_size": Vector2i(16, 16)})
	_eq(r.tileset.get_physics_layers_count(), 0, "physics layers")


func test_full_collision(path: String) -> void:
	_case("collision mode: full")
	var r := TSMBuild.build(_load(path),
		{"tile_size": Vector2i(16, 16), "collision_mode": "full"})
	_eq(r.tileset.get_physics_layers_count(), 1, "physics layers")
	var polys := _polygons(r.tileset, _shape_coords("bottom_half"))
	_eq(polys.size(), 1, "polygon count")
	_eq(polys[0].size(), 4, "polygon points")
	# Godot tile space is centred on the tile, so a full 16x16 tile spans -8..8.
	_eq(polys[0][0], Vector2(-8, -8), "top-left point")
	_eq(polys[0][2], Vector2(8, 8), "bottom-right point")


func test_tight_collision(path: String) -> void:
	_case("collision mode: tight")
	var r := TSMBuild.build(_load(path),
		{"tile_size": Vector2i(16, 16), "collision_mode": "tight"})
	var polys := _polygons(r.tileset, _shape_coords("bottom_half"))
	_eq(polys.size(), 1, "polygon count")
	# Bottom half only: y from 0 to 8 in centred coordinates.
	_eq(polys[0][0], Vector2(-8, 0), "top-left point")
	_eq(polys[0][2], Vector2(8, 8), "bottom-right point")


func test_precise_collision_covers_exactly(path: String) -> void:
	_case("collision mode: precise covers exactly the opaque pixels")
	var r := TSMBuild.build(_load(path),
		{"tile_size": Vector2i(16, 16), "collision_mode": "precise"})
	# The L must decompose into exactly two rectangles whose combined area
	# equals its opaque pixel count - no more (over-cover) and no less (gaps).
	var l_polys := _polygons(r.tileset, _shape_coords("l_shape"))
	_eq(l_polys.size(), 2, "L-shape polygon count")
	var l_area := 0.0
	for p in l_polys:
		l_area += _poly_area(p)
	_eq(l_area, float(Fixtures.SHAPE_AREA["l_shape"]), "L-shape covered area")

	# The checkerboard is the hard case: eight disjoint blocks.
	var c_polys := _polygons(r.tileset, _shape_coords("checker"))
	_eq(c_polys.size(), 8, "checker polygon count")
	var c_area := 0.0
	for p in c_polys:
		c_area += _poly_area(p)
	_eq(c_area, float(Fixtures.SHAPE_AREA["checker"]), "checker covered area")

	# A solid tile is still one rectangle, not 16 rows.
	_eq(_polygons(r.tileset, _shape_coords("full")).size(), 1, "full tile polygon count")


func test_precise_min_area_fallback(path: String) -> void:
	_case("precise: specks fall back to a bounding box")
	var r := TSMBuild.build(_load(path), {
		"tile_size": Vector2i(16, 16), "collision_mode": "precise",
		"collision_min_area": 4,
	})
	var polys := _polygons(r.tileset, _shape_coords("speck"))
	_eq(polys.size(), 1, "speck polygon count")
	_ok(r.report.fallback_tiles >= 1, "a fallback was recorded")
	# With min_area 1 the speck survives as its own 1x1 rectangle.
	var r2 := TSMBuild.build(_load(path), {
		"tile_size": Vector2i(16, 16), "collision_mode": "precise",
		"collision_min_area": 1,
	})
	var polys2 := _polygons(r2.tileset, _shape_coords("speck"))
	_eq(polys2.size(), 1, "speck polygon count at min_area 1")
	_eq(_poly_area(polys2[0]), 1.0, "speck area at min_area 1")


func test_max_polygons_fallback(path: String) -> void:
	_case("precise: too many rectangles fall back to a bounding box")
	var r := TSMBuild.build(_load(path), {
		"tile_size": Vector2i(16, 16), "collision_mode": "precise",
		"collision_max_polygons": 4,
	})
	var polys := _polygons(r.tileset, _shape_coords("checker"))
	_eq(polys.size(), 1, "checker collapses to one polygon")
	_eq(_poly_area(polys[0]), 256.0, "collapsed polygon is the full bounding box")


func test_margins_and_separation(path: String) -> void:
	_case("margins and separation")
	var r := TSMBuild.build(_load(path), {
		"tile_size": Vector2i(8, 8), "margins": Vector2i(2, 2),
		"separation": Vector2i(1, 1), "collision_mode": "full",
	})
	_eq(r.errors.size(), 0, "build errors")
	var atlas := _first_atlas(r.tileset)
	_eq(atlas.get_atlas_grid_size(), Vector2i(2, 2), "atlas grid size")
	_eq(r.report.tiles_created, 2, "tiles created")
	_ok(atlas.get_tile_at_coords(Vector2i(0, 0)) != Vector2i(-1, -1), "tile at (0,0) exists")
	_ok(atlas.get_tile_at_coords(Vector2i(1, 1)) != Vector2i(-1, -1), "tile at (1,1) exists")
	_eq(atlas.get_tile_at_coords(Vector2i(1, 0)), Vector2i(-1, -1), "tile at (1,0) is blank")


func test_image_smaller_than_tile(path: String) -> void:
	_case("image smaller than one tile")
	var r := TSMBuild.build(_load(path), {"tile_size": Vector2i(16, 16)})
	_ok(r.warnings.size() > 0, "a warning is raised")
	_ok(r.errors.size() > 0, "an error is raised rather than a silent empty TileSet")
	_eq(r.report.tiles_created, 0, "no tiles created")


func test_terrain_seeding(path: String) -> void:
	_case("terrain seeding")
	if TSMTerrain == null:
		print("  skipped: terrain seeding is part of Tilesmith Pro, which is not in this tree.")
		return
	var opts := TSMOptions.normalize({
		"tile_size": Vector2i(16, 16), "terrain": true, "terrain_band": 2,
	})
	var r := TSMBuild.build(_load(path), opts)
	_eq(r.errors.size(), 0, "build errors")
	_ok(r.masks.size() > 0, "masks were collected for the terrain pass")
	var t: Dictionary = TSMTerrain.apply(r.tileset, r.masks, opts)
	_eq(t.errors.size(), 0, "terrain errors")
	_eq(r.tileset.get_terrain_sets_count(), 1, "terrain sets")
	_eq(r.tileset.get_terrains_count(0), 1, "terrains in set 0")

	var td := _first_atlas(r.tileset).get_tile_data(_shape_coords("no_top"), 0)
	_eq(td.terrain_set, 0, "terrain set on the tile")
	_eq(td.terrain, 0, "terrain on the tile")
	# The top three rows are transparent, so the three top bits must be unset
	# and the other five set.
	for nb in [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
			TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER]:
		_eq(td.get_terrain_peering_bit(nb), -1, "top peering bit %d is unset" % nb)
	for nb in [TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE,
			TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
			TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER]:
		_eq(td.get_terrain_peering_bit(nb), 0, "peering bit %d is set" % nb)

	# A fully solid tile connects on all eight sides.
	var full_td := _first_atlas(r.tileset).get_tile_data(_shape_coords("full"), 0)
	var set_bits := 0
	for nb in TSMTerrain.NEIGHBOURS:
		if full_td.get_terrain_peering_bit(nb) == 0:
			set_bits += 1
	_eq(set_bits, 8, "peering bits on a solid tile")


func test_save_and_reload_round_trip(path: String) -> void:
	_case("save and reload round trip")
	var r := TSMBuild.build(_load(path),
		{"tile_size": Vector2i(16, 16), "collision_mode": "precise"})
	var out_path := "res://tests/_gen/roundtrip.tres"
	_eq(ResourceSaver.save(r.tileset, out_path), OK, "save result")
	var reloaded := ResourceLoader.load(out_path, "TileSet", ResourceLoader.CACHE_MODE_IGNORE) as TileSet
	_ok(reloaded != null, "reloaded TileSet is not null")
	if reloaded == null:
		return
	_eq(reloaded.tile_size, Vector2i(16, 16), "tile size survives")
	var a := _first_atlas(r.tileset)
	var b := _first_atlas(reloaded)
	_eq(b.get_tiles_count(), a.get_tiles_count(), "tile count survives")
	var coords := _shape_coords("l_shape")
	var before := _polygons(r.tileset, coords)
	var after: Array = []
	var td := b.get_tile_data(coords, 0)
	for i in td.get_collision_polygons_count(0):
		after.append(td.get_collision_polygon_points(0, i))
	_eq(after.size(), before.size(), "polygon count survives")
	for i in before.size():
		_eq(after[i], before[i], "polygon %d points survive" % i)


## The dock is the surface a buyer actually touches, so it gets built for real -
## every control instantiated and read back - rather than trusted.
func test_dock_constructs_and_reads_back(path: String) -> void:
	_case("dock constructs and reads back its own controls")
	var dock_script := load("res://addons/tilesmith/ui/tsm_dock.gd")
	var dock = dock_script.new()
	root.add_child(dock)
	_ok(dock.get_child_count() > 0, "dock built its UI")

	var opts: Dictionary = dock.collect_options()
	_eq(TSMOptions.validate(TSMOptions.normalize(opts)).size(), 0,
		"the dock's own defaults are valid options")
	_eq(opts.tile_size, Vector2i(16, 16), "default tile size")
	_eq(opts.collision_mode, "none", "default collision mode")

	# Drive the controls the way a user would, then confirm the values come back
	# out - a dock that reads a stale control is the classic silent UI defect.
	dock._tile_x.value = 32
	dock._tile_y.value = 24
	dock._collision.selected = TSMOptions.COLLISION_MODES.find("precise")
	dock._min_area.value = 9
	dock._recursive.button_pressed = true
	var changed: Dictionary = dock.collect_options()
	_eq(changed.tile_size, Vector2i(32, 24), "tile size after editing")
	_eq(changed.collision_mode, "precise", "collision mode after editing")
	_eq(changed.collision_min_area, 9, "min area after editing")
	_eq(changed.recursive, true, "recursive after editing")
	_eq(TSMOptions.validate(TSMOptions.normalize(changed)).size(), 0, "edited options are valid")

	# Whatever the dock collects must be something build() accepts.
	var r := TSMBuild.build(_load(path), dock.collect_options())
	_ok(r.tileset != null or r.errors.size() > 0, "build responds to dock options without crashing")

	root.remove_child(dock)
	dock.free()
