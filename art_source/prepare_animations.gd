extends SceneTree

const SET_SCRIPT = preload("res://scripts/crowd_animation_set.gd")
const IDS = ["civilian_normal_a", "civilian_child_a", "civilian_elder_a", "civilian_brute_a", "civilian_journalist_a", "police_officer_a", "swat_officer_a", "patient_zero", "civilian_normal_b", "civilian_normal_c"]
func _initialize() -> void:
	for id in IDS:
		var base: String = "res://assets/animations/" + id
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
		var bytes := FileAccess.get_file_as_bytes(base + "_bones.bin")
		assert(bytes.size() == int(meta.width) * int(meta.height) * 16)
		var image := Image.create_from_data(meta.width, meta.height, false, Image.FORMAT_RGBAF, bytes)
		var packed := load(base + "_gpu.glb") as PackedScene
		var node := packed.instantiate()
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		assert(meshes.size() == 1)
		var mesh: Mesh = meshes[0].mesh
		assert(mesh.get_surface_count() == 1)
		assert(not mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2].is_empty())
		var data := SET_SCRIPT.new()
		data.mesh = mesh
		data.palette = (mesh.surface_get_material(0) as StandardMaterial3D).albedo_texture
		data.bone_texture = ImageTexture.create_from_image(image)
		data.bone_count = meta.bones.size()
		data.clips = meta.clips
		assert(ResourceSaver.save(data, base + "_crowd.res") == OK)
		node.free()
	print("ANIMATION_RESOURCES_BUILT ", IDS.size())
	quit()
