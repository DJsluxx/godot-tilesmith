@tool
extends RefCounted
##
## Build options, their defaults, and validation.
##
## Options are a plain Dictionary so the dock, the CLI and the test suite all
## feed the builder through exactly one door. normalize() is the only place a
## default is ever applied.
##

const COLLISION_MODES := ["none", "full", "tight", "precise"]

const DEFAULTS := {
	# Size of one tile in pixels.
	"tile_size": Vector2i(16, 16),
	# Blank border around the whole sheet, and gap between tiles.
	"margins": Vector2i(0, 0),
	"separation": Vector2i(0, 0),
	# A cell with no pixel at or above this alpha is treated as blank and is not
	# turned into a tile. Deliberately low so faint antialiasing still counts.
	"empty_threshold": 0.01,
	# none  - no physics layer touched
	# full  - one rectangle covering the whole tile
	# tight - one rectangle around the opaque pixels
	# precise - the opaque area decomposed into convex rectangles
	"collision_mode": "none",
	"collision_threshold": 0.5,
	"collision_min_area": 4,
	# Above this many rectangles a tile falls back to its tight bounding box,
	# so a noisy sprite cannot produce hundreds of collision shapes.
	"collision_max_polygons": 12,
	# PRO. Seeds terrain (autotile) peering bits from edge opacity.
	"terrain": false,
	"terrain_threshold": 0.5,
	"terrain_band": 2,
	"terrain_name": "Ground",
	# Search sub-folders when collecting images.
	"recursive": false,
}


## Fill in every missing key with its default. Never mutates the caller's dict.
static func normalize(opts: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate(true)
	for k in opts.keys():
		out[k] = opts[k]
	return out


## Returns an array of human-readable problems. Empty array means valid.
## Every message names the option and the value that was rejected, because a
## validation error a user cannot act on is the same as no validation at all.
static func validate(opts: Dictionary) -> Array:
	var errors: Array = []
	var ts = opts.get("tile_size", Vector2i.ZERO)
	if not (ts is Vector2i):
		errors.append("tile_size must be a Vector2i, got %s." % type_string(typeof(ts)))
	elif ts.x < 1 or ts.y < 1:
		errors.append("tile_size must be at least 1x1 pixels, got %dx%d." % [ts.x, ts.y])

	var mode = opts.get("collision_mode", "none")
	if not (mode is String) or not COLLISION_MODES.has(mode):
		errors.append("collision_mode must be one of %s, got '%s'." % [
			", ".join(COLLISION_MODES), str(mode)])

	for key in ["empty_threshold", "collision_threshold", "terrain_threshold"]:
		var v = opts.get(key, 0.0)
		if not (v is float or v is int):
			errors.append("%s must be a number, got %s." % [key, type_string(typeof(v))])
		elif float(v) < 0.0 or float(v) > 1.0:
			errors.append("%s must be between 0.0 and 1.0, got %s." % [key, str(v)])

	var min_area = opts.get("collision_min_area", 0)
	if not (min_area is int) or min_area < 0:
		errors.append("collision_min_area must be an integer of 0 or more, got %s." % str(min_area))

	var max_poly = opts.get("collision_max_polygons", 1)
	if not (max_poly is int) or max_poly < 1:
		errors.append("collision_max_polygons must be an integer of 1 or more, got %s." % str(max_poly))

	var band = opts.get("terrain_band", 1)
	if not (band is int) or band < 1:
		errors.append("terrain_band must be an integer of 1 or more, got %s." % str(band))
	elif (ts is Vector2i) and ts.x >= 1 and ts.y >= 1 and (band > ts.x or band > ts.y):
		errors.append("terrain_band (%d) is larger than the tile (%dx%d)." % [band, ts.x, ts.y])

	for key in ["margins", "separation"]:
		var v = opts.get(key, Vector2i.ZERO)
		if not (v is Vector2i):
			errors.append("%s must be a Vector2i, got %s." % [key, type_string(typeof(v))])
		elif v.x < 0 or v.y < 0:
			errors.append("%s cannot be negative, got %s." % [key, str(v)])

	return errors
