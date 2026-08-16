extends SceneTree
##
## Smoke test for the FREE edition, run against a project built from the
## extracted free zip - not from the dev tree.
##
## The free edition is the pro tree minus addons/tilesmith/pro/. Every reference
## to that folder is therefore a crash waiting for a buyer, and the pro-tree
## suite can never catch it because in that tree the folder exists.
##

func _initialize() -> void:
	var fails := 0
	var build_script = load("res://addons/tilesmith/core/tsm_build.gd")
	var options_script = load("res://addons/tilesmith/core/tsm_options.gd")

	if not FileAccess.file_exists("res://addons/tilesmith/plugin.cfg"):
		printerr("  FAIL plugin.cfg missing"); fails += 1
	if DirAccess.dir_exists_absolute("res://addons/tilesmith/pro"):
		printerr("  FAIL the free edition still contains a pro/ folder"); fails += 1
	else:
		print("  ok   no pro/ folder present")

	# A real build must still work with pro/ absent.
	var src = build_script.load_source("res://fixtures/shapes.png")
	if not src.ok:
		printerr("  FAIL could not load fixture: " + str(src.error)); fails += 1
	else:
		var r = build_script.build([src],
			{"tile_size": Vector2i(16, 16), "collision_mode": "precise"})
		if r.errors.size() > 0:
			printerr("  FAIL build errors: " + str(r.errors)); fails += 1
		elif r.report.tiles_created != 8:
			printerr("  FAIL expected 8 tiles, got %d" % r.report.tiles_created); fails += 1
		else:
			print("  ok   free build produced 8 tiles with collision")
		if r.tileset != null and ResourceSaver.save(r.tileset, "res://out.tres") != OK:
			printerr("  FAIL could not save the TileSet"); fails += 1

	# Asking for terrain in the free edition must be ignored quietly, never crash.
	var src2 = build_script.load_source("res://fixtures/shapes.png")
	var r2 = build_script.build([src2], {"tile_size": Vector2i(16, 16), "terrain": true})
	if r2.errors.size() > 0:
		printerr("  FAIL terrain flag broke the free build: " + str(r2.errors)); fails += 1
	else:
		print("  ok   terrain flag is harmless in the free edition")

	# The dock must construct with pro/ gone, with terrain disabled.
	var dock_script = load("res://addons/tilesmith/ui/tsm_dock.gd")
	var dock = dock_script.new()
	root.add_child(dock)
	if dock.get_child_count() == 0:
		printerr("  FAIL dock did not build its UI"); fails += 1
	elif not dock._terrain.disabled:
		printerr("  FAIL terrain checkbox is enabled without the pro module"); fails += 1
	else:
		print("  ok   dock builds and disables terrain")
	var opts = dock.collect_options()
	if opts.terrain:
		printerr("  FAIL dock reported terrain enabled"); fails += 1
	if options_script.validate(options_script.normalize(opts)).size() != 0:
		printerr("  FAIL dock defaults are not valid options"); fails += 1
	root.remove_child(dock)
	dock.free()

	print("FREE EDITION SMOKE: %d failed" % fails)
	quit(0 if fails == 0 else 1)
