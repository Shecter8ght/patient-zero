extends SceneTree
const IDS = ["civilian_normal_a", "civilian_child_a", "civilian_elder_a", "civilian_brute_a", "civilian_journalist_a", "police_officer_a", "swat_officer_a", "patient_zero", "civilian_normal_b", "civilian_normal_c"]
var failures: Array[String] = []
var results: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, msg: String) -> void:
	if not ok: failures.append(msg); push_error(msg)
func matrix_at(image: Image, bone: int, frame: int) -> Transform3D:
	var a := image.get_pixel(bone * 3, frame)
	var b := image.get_pixel(bone * 3 + 1, frame)
	var c := image.get_pixel(bone * 3 + 2, frame)
	return Transform3D(Basis(Vector3(a.r,b.r,c.r),Vector3(a.g,b.g,c.g),Vector3(a.b,b.b,c.b)),Vector3(a.a,b.a,c.a))
func run() -> void:
	for id in IDS:
		var data = load("res://assets/animations/" + id + "_crowd.res")
		var node := (load("res://assets/animations/" + id + "_rigged.glb") as PackedScene).instantiate()
		root.add_child(node)
		var ap: AnimationPlayer = node.find_children("*", "AnimationPlayer", true, false)[0]
		var skeleton: Skeleton3D = node.find_children("*", "Skeleton3D", true, false)[0]
		check(skeleton.get_bone_count() == 20, id + ": 17 body and 3 equipment bones")
		var names: Dictionary = {}
		for key in ap.get_animation_list(): names[str(key).get_slice("/", str(key).get_slice_count("/")-1)] = key
		var arrays: Array = data.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var tex: Image = data.bone_texture.get_image()
		var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/animations/"+id+".json"))
		var worst_ground := 0.0
		var clip_rows: Array = []
		for clip: String in data.clips:
			check(names.has(clip), id + ": missing " + clip)
			if not names.has(clip): continue
			var info: Dictionary = data.clips[clip]
			var anim := ap.get_animation(names[clip])
			for prop in ["phone","camera","pistol"]:
				var prop_bone := skeleton.find_bone("prop_"+prop)
				check(prop_bone >= 0,id+": equipment bone "+prop)
				var active_clip: String = {"phone":"phone","camera":"photo","pistol":"shoot"}[prop]
				var gpu_pose := matrix_at(tex,metadata.bones.find("prop_"+prop),int(info.start))
				check(gpu_pose.basis.x.length() > 0.9 if clip == active_clip else gpu_pose.basis.x.length() < 0.001,id+": equipment visibility "+prop+" "+clip)
			check(absf(anim.length - float(info.duration)) < 0.05, id + ": duration " + clip)
			ap.play(names[clip]); ap.seek(0, true); ap.advance(0)
			var first := skeleton.get_bone_pose_rotation(skeleton.find_bone("thigh_L"))
			ap.seek(anim.length * 0.25, true); ap.advance(0)
			var second := skeleton.get_bone_pose_rotation(skeleton.find_bone("thigh_L"))
			if clip in ["walk", "run", "bitten_walk", "bitten_run", "zombie_walk", "zombie_run"]: check(first.angle_to(second) > 0.05, id + ": motion absent " + clip)
			if clip == "bite":
				ap.seek(0, true); ap.advance(0)
				var open := skeleton.get_bone_pose_rotation(skeleton.find_bone("jaw"))
				ap.seek(0.5, true); ap.advance(0)
				check(open.angle_to(skeleton.get_bone_pose_rotation(skeleton.find_bone("jaw"))) > 0.2, id + ": jaw does not bite")
			for offset in [0, int(info.frames) / 2, int(info.frames) - 1]:
				var row: int = int(info.start) + offset
				var matrices: Array[Transform3D] = []
				for bone in data.bone_count: matrices.append(matrix_at(tex, bone, row))
				var ground := INF
				for v in vertices.size():
					var b := clampi(int(floor(uv2[v].x * data.bone_count)), 0, data.bone_count-1)
					ground = minf(ground, (matrices[b] * vertices[v]).y)
				worst_ground = minf(worst_ground, ground)
				check(ground > -0.02, id + ": below ground " + clip + " " + str(ground))
			if info.loop:
				for bone in data.bone_count:
					var a := matrix_at(tex, bone, info.start)
					var b := matrix_at(tex, bone, info.start + info.frames - 1)
					check(a.origin.distance_to(b.origin) < 0.002 and a.basis.x.distance_to(b.basis.x) < 0.002, id + ": loop seam " + clip)
			clip_rows.append(clip)
		results.append({"id": id, "bones": skeleton.get_bone_count(), "clips": clip_rows, "min_ground_y": worst_ground})
		node.free()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var renderer = main.get_node("Agents")
	var player = main.get_node("PlayerView")
	renderer.set_process(false); player.set_process(false)
	check(renderer.batches.size() == 9, "crowd batch count")
	check(renderer.find_children("*", "Skeleton3D", true, false).is_empty(), "per-agent skeletons")
	main.p_vel = Vector2(2,0); player._process(0.016)
	check(player.current_clip == "zombie_walk", "player zombie walk")
	main.sprinting = true; player._process(0.016)
	check(player.current_clip == "zombie_run", "player zombie run")
	main.p_grab = 0; player._process(0.016)
	check(player.current_clip == "bite", "player bite")
	check(player.current_clip == "break_free", "player escape")
	main._throw_cd = Tuning.THROW_CD; player._process(0.016)
	check(player.current_clip == "lunge", "player lunge")
	main.p_grab = -1; main.state[0] = main.S.DEAD; main.health[0] = 0
	renderer._process(0.016)
	check(renderer.clip_names[0] == "fall", "crowd death")
	main.state[1] = main.S.LATENT; renderer._process(0.016)
	main.state[1] = main.S.INFECTED; renderer._process(0.016)
	check(renderer.clip_names[1] == "turning", "crowd turning")
	renderer.turning_left[1] = 0
	main.grab_target[1] = -1; main.phone_timer[1] = 0; main.photo_timer[1] = 0
	main.vel[1] = Vector2(Tuning.INFECTED_SPEED, 0)
	renderer._process(0.016)
	check(renderer.clip_names[1] == "zombie_walk", "infected zombie walk")
	main.vel[1] = Vector2.ZERO; renderer._process(0.016)
	check(renderer.clip_names[1] == "zombie_idle", "infected zombie idle")
	main.state[1] = main.S.INFECTED_COP; renderer.previous_states[1] = main.S.INFECTED_COP
	main.vel[1] = Vector2(Tuning.INFECTED_COP_SPEED, 0); renderer._process(0.016)
	check(renderer.clip_names[1] == "zombie_run", "infected cop zombie run")
	main.grab_target[1] = 2; renderer._process(0.016)
	check(renderer.clip_names[1] == "bite", "infected bite")
	check(renderer.clip_names[2] == "resist", "horde victim resists")
	main.grab_target[1] = -1
	for human_state in [main.S.HEALTHY, main.S.COP]:
		main.state[1] = human_state; main.vel[1] = Vector2(Tuning.CIV_WALK, 0)
		renderer._process(0.016)
		check(renderer.clip_names[1] == "walk", "healthy and police retain normal gait")
	main.state[1] = main.S.LATENT
	main.vel[1] = Vector2(Tuning.CIV_WALK,0); renderer._process(0.016)
	check(renderer.clip_names[1] == "bitten_walk", "bitten intermediate walk")
	main.vel[1] = Vector2(Tuning.CIV_PANIC,0); renderer._process(0.016)
	check(renderer.clip_names[1] == "bitten_run", "bitten intermediate run")
	main.vel[1] = Vector2.ZERO; renderer._process(0.016)
	check(renderer.clip_names[1] == "bitten_idle", "bitten intermediate idle")
	main.reset_run(); renderer._process(0.016); player._process(0.016)
	check(renderer.previous_states.size() == 500, "restart arrays")
	var out := FileAccess.open("res://art_source/animation_validation.json", FileAccess.WRITE)
	out.store_string(JSON.stringify({"passed": failures.is_empty(), "failures": failures, "models": results, "runtime_state_checks": true, "engine": Engine.get_version_info().string}, "\t"))
	print("ANIMATION_VALIDATION ", "PASS" if failures.is_empty() else "FAIL", " models=", results.size())
	main.free()
	quit(0 if failures.is_empty() else 1)
