@tool
extends VBoxContainer
##
## The editor dock. Builds its own UI in code - no .tscn - so the addon is a
## folder of scripts that cannot be broken by a scene format change.
##
## It owns no logic: every button ends in a call to tsm_build.gd, which is the
## same entry point the CLI and the test suite use.
##

const TSMBuild := preload("res://addons/tilesmith/core/tsm_build.gd")
const TSMOptions := preload("res://addons/tilesmith/core/tsm_options.gd")
const PRO_TERRAIN_PATH := "res://addons/tilesmith/pro/tsm_terrain.gd"

var _input_edit: LineEdit
var _output_edit: LineEdit
var _recursive: CheckBox
var _tile_x: SpinBox
var _tile_y: SpinBox
var _margin_x: SpinBox
var _margin_y: SpinBox
var _sep_x: SpinBox
var _sep_y: SpinBox
var _collision: OptionButton
var _empty_threshold: SpinBox
var _collision_threshold: SpinBox
var _min_area: SpinBox
var _max_polys: SpinBox
var _terrain: CheckBox
var _terrain_threshold: SpinBox
var _terrain_band: SpinBox
var _log: RichTextLabel
var _dialog: EditorFileDialog


func _init() -> void:
	name = "Tilesmith"
	add_theme_constant_override("separation", 6)
	# Built here rather than in _ready() so the dock is fully formed the moment
	# it is constructed - the editor reads its minimum size before it is ever
	# added to a tree, and the test suite can drive it without a frame passing.
	_build_ui()


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)

	_heading(body, "Source")
	_input_edit = _path_row(body, "Images", "res://", "Folder of images, or one image file.",
		func(): _pick(true, _input_edit))
	_recursive = _checkbox(body, "Include sub-folders", false)

	_heading(body, "Grid")
	var tile := _pair_row(body, "Tile size", 1, 4096, 16, 16)
	_tile_x = tile[0]
	_tile_y = tile[1]
	var margins := _pair_row(body, "Margins", 0, 4096, 0, 0)
	_margin_x = margins[0]
	_margin_y = margins[1]
	var sep := _pair_row(body, "Separation", 0, 4096, 0, 0)
	_sep_x = sep[0]
	_sep_y = sep[1]
	_empty_threshold = _spin_row(body, "Blank if alpha under", 0.0, 1.0, 0.01, 0.01,
		"Cells with no pixel this opaque become no tile at all.")

	_heading(body, "Collision")
	_collision = OptionButton.new()
	for mode in TSMOptions.COLLISION_MODES:
		_collision.add_item(mode)
	_collision.selected = 0
	_collision.tooltip_text = "none: leave physics alone.\nfull: one rectangle per tile.\ntight: one rectangle around the artwork.\nprecise: the artwork split into convex rectangles."
	_labelled(body, "Shape", _collision)
	_collision_threshold = _spin_row(body, "Solid if alpha over", 0.0, 1.0, 0.01, 0.5,
		"Pixels this opaque count as solid ground.")
	_min_area = _spin_row(body, "Ignore blobs under (px)", 0, 4096, 1, 4,
		"Drops stray antialiased specks.")
	_max_polys = _spin_row(body, "Max shapes per tile", 1, 256, 1, 12,
		"Above this a tile falls back to one bounding box.")

	_heading(body, "Terrain (autotile)")
	var has_pro := ResourceLoader.exists(PRO_TERRAIN_PATH)
	_terrain = _checkbox(body, "Seed terrain peering bits", false)
	_terrain.disabled = not has_pro
	_terrain_threshold = _spin_row(body, "Connect if edge over", 0.0, 1.0, 0.01, 0.5,
		"How full a tile edge must be to count as connected.")
	_terrain_band = _spin_row(body, "Edge sample width (px)", 1, 256, 1, 2,
		"How deep into the tile each edge is sampled.")
	if not has_pro:
		var note := Label.new()
		note.text = "Terrain seeding is part of Tilesmith Pro."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.modulate = Color(1, 1, 1, 0.6)
		body.add_child(note)
		_terrain_threshold.editable = false
		_terrain_band.editable = false

	_heading(body, "Output")
	_output_edit = _path_row(body, "Save to", "res://tileset.tres",
		"Where the .tres TileSet is written.", func(): _pick(false, _output_edit))

	var build_button := Button.new()
	build_button.text = "Build TileSet"
	build_button.pressed.connect(_on_build)
	body.add_child(build_button)

	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(0, 140)
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.text = "Pick a folder of images and a tile size, then press Build."
	body.add_child(_log)


# ------------------------------------------------------------------ ui parts

func _heading(parent: Node, text: String) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	parent.add_child(label)


func _labelled(parent: Node, text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)


func _path_row(parent: Node, text: String, default_value: String, tooltip: String,
		on_browse: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = default_value
	edit.tooltip_text = tooltip
	var row := HBoxContainer.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var browse := Button.new()
	browse.text = "..."
	browse.pressed.connect(on_browse)
	row.add_child(browse)
	_labelled(parent, text, row)
	return edit


func _pair_row(parent: Node, text: String, min_v: float, max_v: float,
		default_x: float, default_y: float) -> Array:
	var row := HBoxContainer.new()
	var a := SpinBox.new()
	var b := SpinBox.new()
	for s in [a, b]:
		s.min_value = min_v
		s.max_value = max_v
		s.step = 1
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(s)
	a.value = default_x
	b.value = default_y
	_labelled(parent, text, row)
	return [a, b]


func _spin_row(parent: Node, text: String, min_v: float, max_v: float, step: float,
		default_value: float, tooltip: String = "") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = default_value
	s.tooltip_text = tooltip
	_labelled(parent, text, s)
	return s


func _checkbox(parent: Node, text: String, pressed: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = pressed
	parent.add_child(c)
	return c


func _pick(directory: bool, target: LineEdit) -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = EditorFileDialog.new()
	_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	if directory:
		_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
		_dialog.dir_selected.connect(func(p): target.text = p)
	else:
		_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		_dialog.add_filter("*.tres", "TileSet resource")
		_dialog.file_selected.connect(func(p): target.text = p)
	add_child(_dialog)
	_dialog.popup_centered_ratio(0.6)


# -------------------------------------------------------------------- action

func collect_options() -> Dictionary:
	return {
		"tile_size": Vector2i(int(_tile_x.value), int(_tile_y.value)),
		"margins": Vector2i(int(_margin_x.value), int(_margin_y.value)),
		"separation": Vector2i(int(_sep_x.value), int(_sep_y.value)),
		"empty_threshold": _empty_threshold.value,
		"collision_mode": TSMOptions.COLLISION_MODES[_collision.selected],
		"collision_threshold": _collision_threshold.value,
		"collision_min_area": int(_min_area.value),
		"collision_max_polygons": int(_max_polys.value),
		"terrain": _terrain.button_pressed and not _terrain.disabled,
		"terrain_threshold": _terrain_threshold.value,
		"terrain_band": int(_terrain_band.value),
		"recursive": _recursive.button_pressed,
	}


func _on_build() -> void:
	_log.clear()
	var input := _input_edit.text.strip_edges()
	var output := _output_edit.text.strip_edges()
	var opts := collect_options()

	var problems: Array = TSMOptions.validate(TSMOptions.normalize(opts))
	if input == "":
		problems.append("Pick a folder of images first.")
	if not output.get_extension().to_lower() in ["tres", "res"]:
		problems.append("The output path must end in .tres.")
	if not problems.is_empty():
		_say_all(problems, "ff8a80")
		return

	var paths: Array = []
	if DirAccess.dir_exists_absolute(input):
		paths = TSMBuild.collect_images(input, opts.recursive)
	elif FileAccess.file_exists(input):
		paths = [input]
	if paths.is_empty():
		_say("No images found in '%s'." % input, "ff8a80")
		return

	var sources: Array = []
	for p in paths:
		var s := TSMBuild.load_source(p)
		if s.ok:
			sources.append(s)
		else:
			_say(s.error, "ff8a80")
	if sources.is_empty():
		return

	var result := TSMBuild.build(sources, opts)
	for w in result.warnings:
		_say(str(w), "ffd54f")
	if not result.errors.is_empty():
		_say_all(result.errors, "ff8a80")
		return

	if opts.terrain and ResourceLoader.exists(PRO_TERRAIN_PATH):
		var terrain_script = load(PRO_TERRAIN_PATH)
		var t: Dictionary = terrain_script.apply(
			result.tileset, result.masks, TSMOptions.normalize(opts))
		_say_all(t.errors, "ff8a80")
		if t.errors.is_empty():
			_say("Terrain: %d tiles seeded, %d peering bits set." % [t.tiles, t.bits_set], "80cbc4")

	var err := ResourceSaver.save(result.tileset, output)
	if err != OK:
		_say("Could not write '%s' (error %d)." % [output, err], "ff8a80")
		return

	var r: Dictionary = result.report
	_say("Built %s" % output, "a5d6a7")
	_say("%d image(s), %d tiles, %d blank cells skipped, %d collision shapes." % [
		r.sources, r.tiles_created, r.cells_skipped, r.collision_polygons])
	if r.fallback_tiles > 0:
		_say("%d tile(s) used a bounding box instead of exact shapes." % r.fallback_tiles, "ffd54f")
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()


func _say(text: String, colour: String = "") -> void:
	if colour == "":
		_log.append_text(text + "\n")
	else:
		_log.append_text("[color=#%s]%s[/color]\n" % [colour, text])


func _say_all(lines: Array, colour: String = "") -> void:
	for line in lines:
		_say(str(line), colour)
