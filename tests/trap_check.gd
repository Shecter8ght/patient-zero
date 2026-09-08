extends SceneTree
## Проверка «ловушки»: запираем здоровых с заражёнными в одной комнате ТЦ
## (дверь закрыта) и смотрим, доводится ли заражение до конца — в замкнутом
## пространстве убежать некуда, зомби загоняют в угол.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_physics_process(false)

	# Комната 1 (NW) на 1-м этаже: x[-22.5,-6], z[6,22.5].
	var room := Rect2(-22.5, 6.0, 16.5, 16.5)
	var inside := room.grow(-1.5)

	var n: int = game.pos.size()
	var placed := 0
	var healthy_ids: Array[int] = []
	for i in n:
		if placed >= 18:
			break
		# Переселяем первых 18 агентов в комнату 1.
		game.floor_idx[i] = 1
		game.pos[i] = Vector2(
			randf_range(inside.position.x, inside.end.x),
			randf_range(inside.position.y, inside.end.y))
		game.dest[i] = Vector2.ZERO
		game.panic[i] = 0.0
		if placed < 3:
			game.state[i] = game.S.INFECTED   # 3 зомби
		else:
			game.state[i] = game.S.HEALTHY    # 15 жертв
			healthy_ids.append(i)
		placed += 1

	# Закрываем единственную дверь комнаты 1 (di=0) на этаже 1.
	game.get_node("/root/MapGen").set_door(1, 0, false)

	var dt := 1.0 / 60.0
	for step in int(60.0 / dt):
		game._physics_process(dt)

	var caught := 0
	for i in healthy_ids:
		if game.state[i] != game.S.HEALTHY:
			caught += 1
	print("TRAP: жертв=%d заражено/убито=%d за 60с" % [healthy_ids.size(), caught])
	if caught >= healthy_ids.size() - 2:
		print("TRAP_OK")
	else:
		printerr("TRAP_WEAK caught=%d/%d" % [caught, healthy_ids.size()])
	quit()
