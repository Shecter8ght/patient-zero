extends SceneTree

var game: Node3D
var failures := 0
var outcomes: Array[int] = []
var blood_events := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
	else:
		print("PASS: " + message)

func fixture() -> void:
	game.reset_run()
	game.set_physics_process(false)
	game.state.fill(game.S.HEALTHY)
	game.has_phone.fill(0)
	game.panic.fill(0)
	game.survivor_role.fill(0)
	game.archetype.fill(Tuning.ARCH_NORMAL)
	game.timer.fill(1000)
	game.floor_cd.fill(1000)
	game._grid.clear()
	game.p_pos = Vector2(-65, -65)
	outcomes.clear()

func run() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.run_finished.connect(func(result: int, _seconds: float): outcomes.append(result))
	game.blood_hit.connect(func(_at: Vector2, _fl: int, _lethal: bool, _direction: Vector2): blood_events += 1)
	fixture()
	for i in 10: game.state[i] = game.S.LATENT
	var counts: Dictionary = game.population_counts()
	check(counts.infected == 10 and counts.latent == 10, "Ten latent agents count as ten infected")
	game._update_agents(0.0)
	check(is_equal_approx(game._infected_frac, 10.0 / Tuning.AGENT_COUNT), "Progress has no double counting")
	for i in 10: game._tick_latent(i, 1001.0)
	counts = game.population_counts()
	check(counts.infected == 10 and counts.latent == 0, "Symptoms do not create more infections")
	fixture()
	for i in 24: game.state[i] = game.S.LATENT
	game._update_agents(0.0)
	check(not game._pending_mutation, "No mutation before 25 infections")
	game.state[24] = game.S.LATENT
	game._update_agents(0.0)
	check(game._pending_mutation and game._next_mut_at == 50, "Mutation at exactly 25 infections")
	fixture()
	for i in 99: game.state[i] = game.S.LATENT
	game._update_agents(0.0)
	check(game.escalation_level == 0, "No escalation before 20 percent")
	game.state[99] = game.S.LATENT
	game._update_agents(0.0)
	check(game.escalation_level == 1, "Escalation at 20 percent")
	fixture()
	game.p_grab = 0
	game._slider_pos = 0.99
	game._resolve_slider()
	check(game.state[0] == game.S.DEAD and blood_events == 1 and game.p_grab == -1, "Kill slider outcome emits blood with correct signature")
	game.p_grab = 1
	game._slider_pos = 0.5
	game._resolve_slider()
	check(game.state[1] == game.S.LATENT and game.p_grab == -1, "Infect slider outcome works")
	game.p_grab = 2
	game._slider_pos = 0.0
	game._resolve_slider()
	check(game.state[2] == game.S.HEALTHY and game.p_grab == -1, "Escape slider outcome works")
	fixture()
	game.state.fill(game.S.DEAD)
	game._finish_run(2)
	game._update_agents(0.0)
	game._finish_run(1)
	check(game.finished == 2 and outcomes == [2], "Defeat cannot be overwritten by victory")
	fixture()
	game.state.fill(game.S.LATENT)
	game._update_agents(0.0)
	check(game.finished == 1 and outcomes == [1] and not game._pending_mutation, "Victory has no pending mutation or duplicate outcome")
	fixture()
	game.state[0] = game.S.COP
	game.floor_idx[0] = game.p_floor
	game.pos[0] = game.p_pos + Vector2(1, 0)
	game.timer[0] = 0
	game.p_health = 1
	game.suspicion = 100
	game._tick_cop(0, 0.01)
	check(game.finished == 2 and outcomes == [2], "Lethal police shot ends the run")
	fixture()
	game.state[0] = game.S.COP
	game.floor_idx[0] = game.p_floor
	game.pos[0] = game.p_pos + Vector2(0.5, 0)
	game.suspicion = Tuning.SUSP_HUNT_PLAYER + 1.0
	game._rebuild_grid()
	game._tick_cop(0, 1.0)
	check(game.finished == 0 and game.p_health == Tuning.AGENT_HEALTH, "Police cannot arrest the player")
	var expected_zones := [
		Vector2(0.34, 0.59), Vector2(0.15, 0.50), Vector2(0.28, 0.55),
		Vector2(0.60, 0.75), Vector2(0.36, 0.59),
	]
	for arch in expected_zones.size():
		check(game.slider_bounds(arch).is_equal_approx(expected_zones[arch]), "Slider zones match archetype %d" % arch)
		var bounds: Vector2 = game.slider_bounds(arch)
		check(1.0 - bounds.y > bounds.y - bounds.x, "Kill zone is wider than infect zone for archetype %d" % arch)
	check(game.slider_bounds(Tuning.ARCH_CHILD).x < game.slider_bounds(Tuning.ARCH_NORMAL).x, "Child has a smaller escape zone")
	check(game.slider_bounds(Tuning.ARCH_BRUTE).x > 0.5, "Brute most often escapes")
	var hud = game.get_node("HUD")
	game.reset_run()
	game.set_physics_process(false)
	await create_timer(1.7, true, false, true).timeout
	check(game.finished == 0 and not hud._story_panel.visible and not hud._menu.visible, "Restart cancels stale result screen")
	hud._set_paused(true)
	var elapsed_before: float = game.elapsed
	game._physics_process(0.01)
	check(game.elapsed == elapsed_before, "Menu pause blocks simulation even with nonzero delta")
	var menu = hud._dev_menu
	check(menu._tabs.get_tab_count() == 3, "Game, reworks and roadmap tabs exist")
	check(menu._tabs.get_tab_title(1) == "Переделки" and menu._tabs.get_tab_title(2) == "Дорожная карта", "Requested tab titles are correct")
	var plan_before := FileAccess.get_file_as_string(menu.PLAN_PATH)
	var accepted_before: bool = menu._checks["rw_launch"].button_pressed
	menu._mark_acceptance(true, "rw_launch")
	menu._save_acceptance()
	menu.refresh()
	check(menu._checks["rw_launch"].button_pressed, "Acceptance survives reload")
	game.reset_run()
	game.set_physics_process(false)
	hud._set_paused(true)
	check(menu._checks["rw_launch"].button_pressed, "Acceptance survives run restart")
	var restore := FileAccess.open(menu.PLAN_PATH, FileAccess.WRITE)
	restore.store_string(plan_before)
	restore.close()
	menu.refresh()
	check(menu._checks["rw_launch"].button_pressed == accepted_before, "Test preserves original acceptance")
	var phase: String = menu._category_bodies.keys()[0]
	var category: Control = menu._category_bodies[phase]
	var header := category.get_parent().get_child(0) as Button
	header.button_pressed = true
	check(category.visible, "Category opens downwards")
	menu._checks["rm_core"].button_pressed = true
	header.button_pressed = false
	check(not category.visible and menu._checks["rm_core"].button_pressed, "Collapsing preserves checkbox state")
	header.button_pressed = true
	menu.refresh()
	check(menu._category_bodies[phase].visible and menu._checks["rm_core"].button_pressed, "Refresh preserves expansion and pending acceptance")
	menu._pending.clear()
	menu.refresh()
	check(not game.has_method("_tick_evac") and not game.has_method("_tick_route_buses"), "Evacuation and route simulation removed")
	hud._set_paused(false)
	game._finish_run(2)
	await create_timer(1.7, true, false, true).timeout
	check(hud._story_panel.visible and hud._story_panel.get_index() > hud._menu.get_index(), "Result chronicle appears above the menu")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	hud._unhandled_input(escape)
	check(not hud._story_panel.visible and hud._menu.visible, "Escape opens menu from result chronicle")
	hud._on_restart_pressed()
	check(game.finished == 0 and Engine.time_scale == 1.0, "Restart after result returns to a running game")
	game.queue_free()
	await process_frame
	print("STAGE1_CHECKS_COMPLETE failures=", failures)
	quit(1 if failures > 0 else 0)
