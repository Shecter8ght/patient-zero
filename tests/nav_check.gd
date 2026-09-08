extends SceneTree
## Стресс-проверка навигации: гоняем симуляцию вручную и смотрим,
## сколько живых агентов застревает (высокий nav_stuck) и как далеко все ушли.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_physics_process(false)   # шагаем вручную, детерминированно

	var n: int = game.pos.size()
	var start := PackedVector2Array()
	start.resize(n)
	for i in n:
		start[i] = game.pos[i]

	var dt := 1.0 / 60.0
	var seconds := 45.0
	var steps := int(seconds / dt)
	for _s in steps:
		game._physics_process(dt)

	# Статистика по ЖИВЫМ агентам (не мёртвым/эвакуированным)
	var stuck := 0
	var moved_far := 0
	var max_stuck := 0.0
	var sum_disp := 0.0
	var alive := 0
	for i in n:
		var st: int = game.state[i]
		if st == game.S.DEAD:
			continue
		alive += 1
		var disp: float = start[i].distance_to(game.pos[i])
		sum_disp += disp
		var s: float = game.nav_stuck[i]
		max_stuck = maxf(max_stuck, s)
		if s > 3.0:
			stuck += 1
		if disp > 3.0:
			moved_far += 1

	var mean_disp := sum_disp / float(maxi(1, alive))
	print("NAV alive=%d stuck(>3s)=%d moved_far(>3m)=%d mean_disp=%.1fm max_stuck=%.1fs"
		% [alive, stuck, moved_far, mean_disp, max_stuck])
	var stuck_frac := float(stuck) / float(maxi(1, alive))
	if stuck_frac < 0.05:
		print("NAV_OK")
	else:
		printerr("NAV_HIGH_STUCK frac=%.2f" % stuck_frac)
	quit()
