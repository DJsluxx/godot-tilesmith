@tool
extends EditorPlugin
##
## Registers the Tilesmith dock. Nothing else - all the work lives in core/.
##

const TSMDock := preload("res://addons/tilesmith/ui/tsm_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = TSMDock.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
