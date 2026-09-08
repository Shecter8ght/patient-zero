extends SceneTree
## Скриншот этажа ТЦ сверху: видны комнаты, стены, двери и распределение толпы.

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var game: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _f in 4: await RenderingServer.frame_post_draw

	# Игрок на 1-м этаже ТЦ, в центре атриума — камера центрируется сюда.
	game.set_physics_process(false)
	game.p_floor = 1
	game.p_pos = Vector2(0.0, 0.0)

	# Прогоняем симуляцию, чтобы толпа разошлась по комнатам через двери.
	var dt := 1.0 / 60.0
	for _s in 300:
		game._physics_process(dt)

	# Камера: широкий ортографический обзор всего этажа сверху.
	var cam := root.get_camera_3d()
	var rig := cam.get_parent()
	rig._prev_floor = 1
	rig._target_size = 52.0
	cam.size = 52.0
	rig.global_position = Vector3(0.0, 0.0, 0.0)   # 1-й этаж ТЦ на высоте 0

	DirAccess.make_dir_recursive_absolute("res://tests/output")
	for _f in 24: await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/output/mall_floor1.png")
	print("MALL_CAPTURE_COMPLETE")
	quit()
