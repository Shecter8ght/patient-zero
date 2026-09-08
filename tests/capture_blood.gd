extends SceneTree
## Крупный план крови: делаем кластер попаданий и смотрим на лужи/потёки сверху.

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var game: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _f in 6: await RenderingServer.frame_post_draw

	var at: Vector2 = game.p_pos
	var fl: int = game.p_floor
	# Несколько раздельных попаданий, чтобы видеть отдельные брызги.
	for _k in 3:
		var off := Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
		var dir := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		game.blood_hit.emit(at + off, fl, true, dir)
	for _k in 3:
		var off := Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
		game.blood_hit.emit(at + off, fl, false, Vector2.RIGHT.rotated(randf() * TAU))

	# Даём жидкости растечься и каплям упасть.
	for _f in 220: await RenderingServer.frame_post_draw

	# Камера — крупный план сверху над лужей.
	var cam := root.get_camera_3d()
	var rig := cam.get_parent()
	rig._prev_floor = fl
	rig._target_size = 12.0
	cam.size = 12.0
	rig.global_position = Vector3(at.x, 0.0, at.y)
	for _f in 14: await RenderingServer.frame_post_draw

	DirAccess.make_dir_recursive_absolute("res://tests/output")
	root.get_texture().get_image().save_png("res://tests/output/blood.png")
	print("BLOOD_CAPTURE_COMPLETE")
	quit()
