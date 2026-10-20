extends SceneTree
## Dev tool: renders a contact sheet of every robot animation.
## Usage (windowed, needs a GPU): godot --path . --script res://tools/anim_preview.gd


const OUT := "res://docs/reference/anim_sheet.png"
const CELL := Vector2i(256, 256)


func _initialize() -> void:
	_run()


func _run() -> void:
	root.size = CELL
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.82, 0.86, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.75)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	world.add_child(sun)
	var robot: Node3D = (load("res://assets/characters/pink_robot/pink_robot.glb") as PackedScene).instantiate()
	world.add_child(robot)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(1.0, 0.75, 1.6), Vector3(0, 0.35, 0))
	cam.fov = 40
	var ap: AnimationPlayer = robot.get_node("AnimationPlayer")
	var anims := ap.get_animation_list()
	var fractions := [0.0, 0.2, 0.4, 0.6, 0.8]
	var sheet := Image.create(CELL.x * fractions.size(), CELL.y * anims.size(), false, Image.FORMAT_RGBA8)
	for row in anims.size():
		ap.play(anims[row])
		for col in fractions.size():
			ap.seek(ap.current_animation_length * fractions[col], true)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(CELL.x, CELL.y)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
		print(row, " ", anims[row])
	sheet.save_png(ProjectSettings.globalize_path(OUT))
	print("saved ", OUT)
	quit()
