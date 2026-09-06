extends Node3D
class_name BarkSystem
## Пузыри с репликами. Текст, без озвучки — тысяча строк стоит час работы,
## тысяча озвученных строк убьёт проект.
##
## Главное правило: реплика — это КАНАЛ ИНФОРМАЦИИ, а не декор.
## Крик «он там!» должен реально передавать позицию соседям (см. sim.gd).
##
## Использование из sim.gd:
##     barks.say(agent_index, "spot_infected", global_pos)

const MAX_VISIBLE := 3          # больше — экран превращается в кашу
const LIFETIME := 2.6
const POOL_SIZE := 8

@export var data_path := "res://data/barks.json"
@export var tone := "grim"      # "grim" | "comic" — переключатель в настройках
@export var language := "ru"    # "ru" | "en"

var _cats := {}
var _agent_cd := {}             # индекс агента -> время следующей реплики
var _global_cd := {}            # категория -> время следующей реплики
var _pool: Array[Label3D] = []
var _active: Array[Dictionary] = []
var _cam: Camera3D


func _ready() -> void:
	_load_data()
	for i in POOL_SIZE:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font_size = 48
		l.pixel_size = 0.006
		l.outline_size = 14
		l.modulate = Color(0.94, 0.93, 0.90)
		l.outline_modulate = Color(0, 0, 0, 0.85)
		l.visible = false
		add_child(l)
		_pool.append(l)
	_cam = get_viewport().get_camera_3d()


func _load_data() -> void:
	var f := FileAccess.open(data_path, FileAccess.READ)
	if f == null:
		push_error("barks.json не найден: %s" % data_path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("barks.json не парсится")
		return
	_cats = parsed.get("categories", {})


func set_tone(new_tone: String) -> void:
	tone = new_tone


func set_language(lang: String) -> void:
	language = lang


## Попытка сказать реплику. Вернёт false, если её отфильтровали.
func say(agent: int, category: String, world_pos: Vector3) -> bool:
	if not _cats.has(category):
		return false
	var cat: Dictionary = _cats[category]
	var now := Time.get_ticks_msec() / 1000.0

	if _agent_cd.get(agent, 0.0) > now:
		return false
	if _global_cd.get(category, 0.0) > now:
		return false

	# Далеко от камеры — не тратим слот
	if _cam and _cam.global_position.distance_to(world_pos) > float(cat.get("radius", 15)) * 1.6:
		return false

	var prio := int(cat.get("priority", 10))
	if _active.size() >= MAX_VISIBLE and not _evict_weaker(prio):
		return false

	var line := _pick_line(cat)
	if line == "":
		return false

	_agent_cd[agent] = now + float(cat.get("cooldown", 8.0))
	_global_cd[category] = now + float(cat.get("global_cooldown", 1.0))
	_show(line, world_pos, prio)
	return true


func _pick_line(cat: Dictionary) -> String:
	var by_lang: Dictionary = cat.get("lines", {}).get(language, {})
	var arr: Array = by_lang.get(tone, [])
	if arr.is_empty():
		# фолбэк: другой тон, потом другой язык — лучше странная реплика, чем пустота
		for t in by_lang.keys():
			if not by_lang[t].is_empty():
				arr = by_lang[t]
				break
	if arr.is_empty():
		return ""
	return str(arr[randi() % arr.size()])


func _evict_weaker(prio: int) -> bool:
	var worst := -1
	var worst_prio := prio
	for i in _active.size():
		if _active[i].prio < worst_prio:
			worst_prio = _active[i].prio
			worst = i
	if worst < 0:
		return false
	_release(worst)
	return true


func _show(text: String, world_pos: Vector3, prio: int) -> void:
	var label: Label3D = null
	for l in _pool:
		if not l.visible:
			label = l
			break
	if label == null:
		return
	label.text = text
	label.global_position = world_pos + Vector3(0, 1.9, 0)
	label.modulate.a = 1.0
	label.visible = true
	_active.append({"label": label, "t": LIFETIME, "prio": prio, "pos": world_pos})


func _process(delta: float) -> void:
	for i in range(_active.size() - 1, -1, -1):
		var e: Dictionary = _active[i]
		e.t -= delta
		var l: Label3D = e.label
		l.global_position = l.global_position.lerp(e.pos + Vector3(0, 2.3, 0), 1.0 - exp(-3.0 * delta))
		if e.t < 0.6:
			l.modulate.a = maxf(0.0, e.t / 0.6)
		if e.t <= 0.0:
			_release(i)


func _release(i: int) -> void:
	var e: Dictionary = _active[i]
	e.label.visible = false
	_active.remove_at(i)
