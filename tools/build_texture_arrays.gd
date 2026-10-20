extends SceneTree
## Dev tool: packs the terrain surface sets (Poly Haven CC0 scans in assets/textures/terrain_src,
## a .gdignore'd folder) into vertical strip atlases that Godot imports as compressed
## Texture2DArrays (albedo, normal, ARM) for shaders/terrain.gdshader.
## Usage: godot --headless --path . --script res://tools/build_texture_arrays.gd
##        then godot --headless --path . --import

## Layer order is the contract with terrain.gdshader.
const LAYERS := [
	"sparse_grass",       # 0 meadow / shrine / garden ground
	"stony_dirt_path",    # 1 dirt path
	"forest_ground_04",   # 2 forest floor
	"cliff_side",         # 3 rock slopes and cliffs
	"mossy_cobblestone",  # 4 shrine paving / path
	"gravelly_sand",      # 5 garden path
	"brown_mud_02",       # 6 wet shores
	"mossy_rock",         # 7 moss on hill rock (shared with props, so it lives in assets/textures)
]
const SIZE := 1024
const SRC := "res://assets/textures/terrain_src/"
const OUT := "res://assets/textures/terrain/"

const IMPORT_TEMPLATE := """[remap]

importer="2d_array_texture"
type="CompressedTexture2DArray"

[deps]

source_file="%s"

[params]

compress/mode=2
compress/high_quality=true
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/channel_pack=%d
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal=1
slices/vertical=%d
"""


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for kind in ["diff", "nor", "arm"]:
		var atlas := Image.create_empty(SIZE, SIZE * LAYERS.size(), false, Image.FORMAT_RGB8)
		for i in LAYERS.size():
			var layer: String = LAYERS[i]
			var path := ProjectSettings.globalize_path(SRC + "%s/%s_%s.jpg" % [layer, layer, kind])
			if not FileAccess.file_exists(path):
				path = ProjectSettings.globalize_path("res://assets/textures/%s/%s_%s.jpg" % [layer, layer, kind])
			var img := Image.load_from_file(path)
			if img == null or img.is_empty():
				push_error("Missing texture " + path)
				quit(1)
				return
			img.convert(Image.FORMAT_RGB8)
			if img.get_width() != SIZE:
				img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
			atlas.blit_rect(img, Rect2i(0, 0, SIZE, SIZE), Vector2i(0, i * SIZE))
		var res_path := OUT + "terrain_%s.png" % kind
		var err := atlas.save_png(ProjectSettings.globalize_path(res_path))
		if err != OK:
			push_error("Saving %s failed: %s" % [res_path, error_string(err)])
			quit(1)
			return
		# channel_pack 0 = sRGB friendly (albedo), 1 = optimized (linear data maps).
		var import_text := IMPORT_TEMPLATE % [res_path, 0 if kind == "diff" else 1, LAYERS.size()]
		var f := FileAccess.open(ProjectSettings.globalize_path(res_path + ".import"), FileAccess.WRITE)
		f.store_string(import_text)
		f.close()
		print("saved ", res_path, " ", atlas.get_size())
	quit()
