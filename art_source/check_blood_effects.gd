extends SceneTree
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	var fx = game.get_node("BloodEffects")
	fx.set_process(false)
	fx.clear()
	game.p_floor = 0
	game.p_grab = -1
	game.grab_target.fill(-1)
	game.blood_hit.emit(Vector2(0,-35),0,true,Vector2.RIGHT)
	check(fx.pools.size() == 1 and fx.drops.size() == Tuning.BLOOD_DEATH_DROPS,"death event creates pool and spray")
	fx._process(0.2)
	check(fx.blood_clock > 0 and fx.drops[0].pos.y < 1.6,"effects animate")
	check(fx.visible_mark_count() == 1,"street blood visible")
	game.p_floor = 2
	fx._process(0.1)
	check(fx.visible_mark_count() == 0 and fx.droplets.multimesh.visible_instance_count == 0,"other floors hidden")
	game.blood_hit.emit(Vector2.ZERO,2,false,Vector2.UP)
	fx._process(0.1)
	check(fx.visible_mark_count() == 1,"mall blood visible")
	check(absf(fx.pools[1].pos.y - root.get_node("MapGen").floor_y3d(2) - 0.012) < 0.001,"mall floor elevation")
	var age: float = fx.blood_clock
	game.finished = 1
	fx._process(1.0)
	check(is_equal_approx(fx.blood_clock,age),"finished game freezes effects")
	game.finished = 0
	fx.clear()
	game.p_floor = 0
	game.pos[0] = Vector2(0,-35)
	game.state[0] = game.S.HEALTHY
	game.floor_idx[0] = 0
	game.p_grab = 0
	fx._process(0.1)
	check(fx.pools.size() == 1,"player bite produces blood")
	game.p_grab = -1
	fx.clear()
	game.state[1] = game.S.INFECTED
	game.grab_target[1] = 0
	fx._process(0.1)
	check(fx.pools.size() == 1,"horde bite produces blood")
	game.grab_target[1] = -1
	fx.clear()
	game.state[1] = game.S.COP
	game.grab_target[1] = 0
	fx._process(0.1)
	check(fx.pools.is_empty(),"police restraint does not bleed")
	game.grab_target[1] = -1
	for i in 1000: fx.emit_hit(Vector2(i*2,0),0,false,Vector2.RIGHT)
	check(fx.pools.size() == 1000 and fx.drops.size() == Tuning.BLOOD_DROP_COUNT,"permanent traces exceed old limit; airborne drops remain bounded")
	var original: Vector3 = fx.pools[0].pos
	var birth: float = fx.pools[0].born
	fx._process(3600.0)
	check(fx.pools.size() >= 1000 and fx.drops.is_empty(),"blood persists after an hour")
	check(fx.pools[0].pos == original and fx.pools[0].born == birth,"oldest mark survives new batches and time")
	var volume: float = fx.pools[0].volume
	fx.emit_hit(Vector2.ZERO,0,false,Vector2.RIGHT)
	check(fx.pools[0].volume > volume and fx.pools[0].pos == original and fx.pools[0].born == birth,"feeding a trace does not move it or reset the flow")
	game.p_floor = 1; fx._process(0)
	check(fx.visible_mark_count() == 0,"stored blood hides on floor switch")
	game.p_floor = 0; fx._process(0)
	check(fx.visible_mark_count() >= 1000,"all permanent marks return on revisiting floor")
	fx.emit_hit(Vector2.ZERO,0,true,Vector2.RIGHT)
	game.reset_run()
	check(fx.pools.is_empty() and fx.drops.is_empty(),"restart clears effects immediately")
	game.p_grab = -1
	game.grab_target.fill(-1)
	game.state[0] = game.S.DEAD
	game.health[0] = 1
	fx._process(0.1)
	check(fx.pools.is_empty(),"state change alone does not produce blood")
	game.state[0] = game.S.INFECTED
	game.pos[0] = Vector2(0,-40)
	game.floor_idx[0] = 0
	game.health[0] = Tuning.AGENT_HEALTH
	game.state[1] = game.S.COP
	game.pos[1] = Vector2(0,-42)
	game.floor_idx[1] = 0
	game.p_pos = Vector2(30,-40)
	game._rebuild_grid()
	for i in 100:
		game.alert[1] = 3
		game.alert_target[1] = 0
		game.timer[1] = 0
		game._tick_cop(1,0.016)
		if game.state[0] == game.S.DEAD: break
	check(game.state[0] == game.S.DEAD and game.health[0] == 0,"actual lethal shot marks visible corpse")
	check(not fx.pools.is_empty(),"actual police shot triggers blood")
	fx.set_process(true)
	paused = true
	age = fx.blood_clock
	for i in 3: await process_frame
	check(is_equal_approx(fx.blood_clock,age),"tree pause freezes effects")
	paused = false
	var report := {"passed":failures.is_empty(),"failures":failures,"permanent_marks_tested":1000,"retention_seconds_tested":3600,"batch_size":Tuning.BLOOD_MARK_BATCH_SIZE,"particle_limit":Tuning.BLOOD_DROP_COUNT}
	FileAccess.open("res://art_source/blood_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("BLOOD_CHECK ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
