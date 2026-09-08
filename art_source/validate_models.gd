extends SceneTree

var failures: Array[String] = []
var rows: Array = []

func _initialize() -> void:
	call_deferred("validate")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func validate() -> void:
	var manifest: Array = JSON.parse_string(FileAccess.get_file_as_string("res://art_source/model_manifest.json"))
	for item: Dictionary in manifest:
		var packed := load("res://" + str(item.glb)) as PackedScene
		check(packed != null, str(item.id) + ": cannot import")
		if packed == null: continue
		var instance := packed.instantiate() as Node3D
		root.add_child(instance)
		var meshes: Array[MeshInstance3D] = []
		collect(instance, meshes)
		check(meshes.size() == int(item.mesh_count), str(item.id) + ": mesh count")
		var bounds := AABB()
		var first := true
		var surfaces := 0
		var triangles := 0
		for mi in meshes:
			var box: AABB = mi.global_transform * mi.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			surfaces += mi.mesh.get_surface_count()
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
				check(mat != null and mat.albedo_texture != null, str(item.id) + ": missing palette texture")
				var arrays := mi.mesh.surface_get_arrays(s)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				triangles += indices.size() / 3
		var expected: Array = item.dimensions_godot_xyz
		check(bounds.size.is_equal_approx(Vector3(expected[0], expected[1], expected[2])) or bounds.size.distance_to(Vector3(expected[0], expected[1], expected[2])) < 0.002, str(item.id) + ": incorrect dimensions")
		if item.category == "characters":
			check(surfaces == 1, str(item.id) + ": crowd requires one surface")
			check(absf(bounds.position.y) < 0.002, str(item.id) + ": feet not on ground")
			check(instance.position.length() < 0.001, str(item.id) + ": root origin")
		check(triangles == int(item.triangles), str(item.id) + ": triangle mismatch")
		rows.append({"id": item.id, "meshes": meshes.size(), "surfaces": surfaces, "triangles": triangles, "bounds": str(bounds), "imported": true})
		instance.free()
	var report := {"godot_version": Engine.get_version_info(), "assets": rows, "failures": failures, "passed": failures.is_empty()}
	var file := FileAccess.open("res://art_source/godot_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("MODEL_VALIDATION ", "PASS" if failures.is_empty() else "FAIL", " assets=", rows.size())
	quit(0 if failures.is_empty() else 1)

func collect(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D: meshes.append(node)
	check(not (node is CollisionObject3D or node is Light3D or node is Camera3D or node is Skeleton3D), str(node.name) + ": unexpected runtime node")
	for child in node.get_children(): collect(child, meshes)
