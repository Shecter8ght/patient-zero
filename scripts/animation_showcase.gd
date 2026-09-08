extends Node3D
const SETS = preload("res://scripts/agent_renderer.gd").SETS
const SHADER = preload("res://assets/shaders/crowd_bones.gdshader")
const PLAYER = preload("res://assets/animations/patient_zero_rigged.glb")
const PLAYER_GPU = preload("res://assets/animations/patient_zero_crowd.res")
const CLIPS = ["zombie_idle", "zombie_walk", "zombie_run", "bite", "idle", "walk", "run", "grab", "resist", "turning", "fall", "arrested", "break_free", "lunge", "phone", "photo", "shoot"]
var active_clip := 1
var clock := 0.0
var batches: Array[MultiMeshInstance3D] = []
var data_sets: Array = []
var animation: AnimationPlayer
var title: Label

func _ready() -> void:
	for i in SETS.size(): add_gpu(SETS[i], Vector3((i-3.0)*1.22, 0, 0))
	add_gpu(PLAYER_GPU, Vector3(1.1,0,3))
	var player := PLAYER.instantiate()
	add_child(player)
	player.position = Vector3(-1.1,0,3)
	animation = player.find_children("*", "AnimationPlayer", true, false)[0]
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new(); plane.size = Vector2(50,50)
	ground.mesh = plane
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color("29333b")
	ground.material_override = mat; ground.position.y = -0.018; add_child(ground)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-50,-25,0)
	light.shadow_enabled = true; light.light_energy = 1.25; add_child(light)
	var world := WorldEnvironment.new(); world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR; world.environment.background_color = Color("202830")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("bdcbd4"); world.environment.ambient_light_energy = 0.65
	add_child(world)
	var camera := Camera3D.new(); add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 7.5
	camera.position = Vector3(5,8,13); camera.look_at(Vector3(0,0.8,1));camera.current = true
	var ui := CanvasLayer.new(); add_child(ui); title = Label.new();title.position = Vector2(24,20); ui.add_child(title)
	set_clip("zombie_walk")

func add_gpu(data: Resource, position3: Vector3) -> void:
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = MultiMesh.new();batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.use_colors = true;batch.multimesh.use_custom_data = true;batch.multimesh.mesh = data.mesh
	batch.multimesh.instance_count = 1
	batch.multimesh.set_instance_transform(0, Transform3D(Basis(), position3))
	batch.multimesh.set_instance_color(0,Color.WHITE)
	batch.custom_aabb = AABB(Vector3(-10,-2,-10),Vector3(20,10,20))
	var mat := ShaderMaterial.new();mat.shader = SHADER
	mat.set_shader_parameter("bone_texture",data.bone_texture);mat.set_shader_parameter("palette",data.palette)
	mat.set_shader_parameter("bone_count",data.bone_count);batch.material_override = mat
	add_child(batch);batches.append(batch);data_sets.append(data)

func set_clip(clip: String) -> void:
	active_clip = CLIPS.find(clip);clock = 0.0
	animation.play(clip)
	title.text = "PATIENT ZERO / " + clip.to_upper() + "\nSpace: next clip | Back row: GPU crowd | Front: skeletal / GPU player"
	advance(0)

func advance(delta: float) -> void:
	clock += delta
	var clip: String = CLIPS[active_clip]
	for i in batches.size():
		var info: Dictionary = data_sets[i].clips[clip]
		var t := fmod(clock,float(info.duration)) if info.loop else minf(clock,float(info.duration))
		var row: float = info.start + t / float(info.duration) * (info.frames - 1)
		batches[i].multimesh.set_instance_custom_data(0,Color(row,row,1,0))
	var info: Dictionary = PLAYER_GPU.clips[clip]
	var t := fmod(clock,float(info.duration)) if info.loop else minf(clock,float(info.duration))
	animation.seek(t,true); animation.advance(0)

func _process(delta: float) -> void: advance(delta)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		set_clip(CLIPS[(active_clip+1)%CLIPS.size()])
