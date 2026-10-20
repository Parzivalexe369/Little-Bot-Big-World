class_name InputGlyphs
extends RefCounted
## Short key/button labels for prompts, following whichever device was used last.

static var using_gamepad := false

const KEYS := {
	"interact": "E", "scan": "Q", "hop": "Space", "boost": "Shift", "pause": "Esc", "journal": "J",
	"move": "WASD", "look": "Mouse",
}
const PAD := {
	"interact": "X", "scan": "Y", "hop": "A", "boost": "RT", "pause": "Start", "journal": "Back",
	"move": "L-Stick", "look": "R-Stick",
}
## Names of the on-screen touch buttons (see TouchControls).
const TOUCH := {
	"interact": "USE", "scan": "SCAN", "hop": "HOP", "boost": "BOOST", "pause": "Pause", "journal": "Journal",
	"move": "Left stick", "look": "Drag",
}


static func label(action: String) -> String:
	if TouchControls.active:
		return TOUCH.get(action, action)
	return (PAD if using_gamepad else KEYS).get(action, action)


static func observe(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.4):
		using_gamepad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		using_gamepad = false
