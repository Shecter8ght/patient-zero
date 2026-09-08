extends SceneTree
## Прогноз каскада БЕЗ действий игрока: подсаживаем заражённых в толпу и смотрим,
## растёт ли охват сам по себе (латентная инфильтрация + добивание неспаниковавших)
## или глохнет из-за того, что паникующие убегают быстрее зомби.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_physics_process(false)

	var n: int = game.pos.size()
	# Сеем 6 заражённых среди агентов 1-го этажа ТЦ (floor 1): 3 активных + 3 латентных.
	var seeded := 0
	for i in n:
		if game.floor_idx[i] == 1 and game.state[i] == game.S.HEALTHY:
			if seeded < 3:
				game.state[i] = game.S.INFECTED
			else:
				game.state[i] = game.S.LATENT
				game.timer[i] = game.incubation_eff
			seeded += 1
			if seeded >= 6:
				break

	var dt := 1.0 / 60.0
	var marks := [30, 60, 120, 180, 240]
	var mi := 0
	var total := int(dt * 0)   # 0
	for step in int(240.0 / dt):
		game._physics_process(dt)
		var t := float(step + 1) * dt
		if mi < marks.size() and t >= marks[mi]:
			print("t=%3ds  %s" % [marks[mi], _snapshot(game, n)])
			mi += 1
	total = total
	quit()

func _snapshot(game: Node3D, n: int) -> String:
	var inf := 0
	var lat := 0
	var dead := 0
	var healthy := 0
	for i in n:
		match game.state[i]:
			game.S.INFECTED, game.S.INFECTED_COP: inf += 1
			game.S.LATENT: lat += 1
			game.S.DEAD: dead += 1
			game.S.HEALTHY: healthy += 1
	var covered := inf + lat + dead
	var pct := 100.0 * float(covered) / float(n)
	return "охват=%5.1f%%  активных=%d латентных=%d мёртвых=%d здоровых=%d" % [pct, inf, lat, dead, healthy]
