class_name Minigame
extends Control
## Base for the overlay minigames. Main listens to `hint` (shows the simple
## dialog panel, or hides it with an empty dictionary) and `completed`.

signal completed
signal hint(panel: Dictionary)

## True while a story dialog is on screen — minigames pause and dim.
var dialog_active := false:
	set(v):
		var changed := dialog_active != v
		dialog_active = v
		if changed:
			_on_dialog_active_changed()
			queue_redraw()

var _done := false


func _ready() -> void:
	size = Vector2(1066, 600)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _on_dialog_active_changed() -> void:
	pass


func finish(delay := 0.0) -> void:
	if _done:
		return
	_done = true
	if delay > 0:
		await get_tree().create_timer(delay).timeout
	completed.emit()


func _unhandled_input(event: InputEvent) -> void:
	# X skips the minigame (debug shortcut from the web build).
	if not dialog_active and event.is_action_pressed("skip_minigame"):
		finish()
