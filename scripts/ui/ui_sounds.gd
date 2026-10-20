class_name UiSounds
extends RefCounted
## Hooks soft UI sounds onto every button/slider under a control.


static func wire(root: Node) -> void:
	for node in root.find_children("*", "BaseButton", true, false):
		var b := node as BaseButton
		if b.has_meta(&"ui_wired"):
			continue
		b.set_meta(&"ui_wired", true)
		b.focus_entered.connect(func() -> void: Audio.play_ui(&"ui_move", -8.0))
		b.mouse_entered.connect(func() -> void:
			if not b.disabled:
				b.grab_focus())
		b.pressed.connect(func() -> void: Audio.play_ui(&"ui_confirm", -4.0))
