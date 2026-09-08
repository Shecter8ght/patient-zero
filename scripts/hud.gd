extends CanvasLayer

@export var sim_path: NodePath
var sim: Node3D
var bar:       ProgressBar
var label:     Label
var _menu:     Control   # меню паузы
var _mut_panel: Control  # панель выбора мутации
var _ticker: VBoxContainer         # строка состояния: неблокирующие уведомления
var _ticker_msgs: Array = []       # [{ctrl: Control, t: float, dur: float}]
var _paused    := false
var _run_revision := 0
var _dev_menu: Control

var _story_panel:  Control
var _story_scroll: ScrollContainer
var _story_text:   RichTextLabel

var _grab_panel:  Control
var _grab_cursor: ColorRect
var _grab_zones: Array[ColorRect] = []
var _grab_zone_target := -1


func _ready() -> void:
	sim   = get_node(sim_path)
	bar   = $Root/Suspicion
	label = $Root/Status

	_build_menu()
	_build_mut_panel()
	_build_ticker()
	_build_story_panel()
	_build_grab_slider()

	sim.stats_changed.connect(_on_stats)
	sim.run_finished.connect(_on_finished)
	sim.mutation_available.connect(_on_mutation_available)
	sim.escalation_triggered.connect(_on_escalation)
	sim.visuals_reset.connect(_on_run_reset)
	sim.door_toggled.connect(_on_door_toggled)


func _build_menu() -> void:
	_dev_menu = preload("res://scripts/development_menu.gd").new()
	_menu = _dev_menu
	$Root.add_child(_menu)
	_dev_menu.resume_requested.connect(func(): _set_paused(false))
	_dev_menu.restart_requested.connect(_on_restart_pressed)
	_menu.visible = false


func _set_paused(value: bool) -> void:
	_paused = value
	_menu.visible = value
	Engine.time_scale = 0.0 if value else 1.0
	sim.holding = false
	sim.sprinting = false
	if value:
		$Root.move_child(_menu, -1)
		_dev_menu.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _story_panel.visible:
			_story_panel.visible = false
			_set_paused(true)
		else:
			_set_paused(not _paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		_on_restart_pressed()
		get_viewport().set_input_as_handled()


func _on_restart_pressed() -> void:
	sim.reset_run()


func _on_run_reset() -> void:
	_run_revision += 1
	_set_paused(false)
	_story_panel.visible = false
	_mut_panel.visible = false
	_clear_ticker()
	_grab_panel.visible = false
	_grab_zone_target = -1


func _clear_ticker() -> void:
	for m: Dictionary in _ticker_msgs:
		(m["ctrl"] as Control).queue_free()
	_ticker_msgs.clear()


func _on_stats(_healthy: int, infected: int, latent: int, dead: int,
		cops: int, suspicion: float) -> void:
	bar.value = suspicion

	var pct := roundi(float(infected + dead) / maxf(1.0, sim.pos.size()) * 100.0)
	var horde_str := ""
	match sim.horde_cmd:
		sim.HC_FOLLOW:
			horde_str = "\n> ОРДА — СЛЕДОВАТЬ [F — отмена]"
		sim.HC_HOLD:
			horde_str = "\n> ОРДА — УДЕРЖАНИЕ [H — отмена]"
		sim.HC_ATTACK:
			var ta: int = sim.horde_target_agent
			var lbl := "КОП" if (ta >= 0 and sim.state[ta] == sim.S.COP) else "ЦЕЛЬ"
			horde_str = "\n> ОРДА — АТАКА %s (%.0f сек)" % [lbl, sim.horde_target_life]
		sim.HC_MOVE:
			horde_str = "\n> ОРДА — ДВИЖЕНИЕ (%.0f сек)" % sim.horde_target_life
	var mins := int(sim.elapsed) / 60
	var secs := int(sim.elapsed) % 60
	var time_str := "%d:%02d" % [mins, secs] if mins > 0 else "%d сек" % secs
	label.text = (
		"Охват города: %d%%   Активных: %d   Без симптомов: %d   [%s]\n" +
		"Мертвых: %d   Полиции: %d   Подозрение: %d\n" +
		"Охват = заражённые + погибшие. Цель: %d%%\n" +
		"ЛКМ захват   ПКМ движение/атака   F следовать   H удержание   Esc пауза"
	) % [pct, infected - latent, latent, time_str, dead, cops, roundi(suspicion),
		roundi(Tuning.WIN_RATIO * 100.0)] + horde_str

	var st := bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	if st:
		st.bg_color = (
			Color(0.89, 0.29, 0.29) if suspicion > 70.0
			else (Color(0.94, 0.62, 0.15) if suspicion > 35.0
			else Color(0.39, 0.60, 0.13))
		)
		bar.add_theme_stylebox_override("fill", st)


func _build_mut_panel() -> void:
	_mut_panel = Control.new()
	_mut_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mut_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_mut_panel.visible = false

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.80)
	_mut_panel.add_child(bg)

	var title := Label.new()
	title.text = "МУТАЦИЯ"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_top    = 80
	title.offset_left   = -200
	title.offset_right  =  200
	title.offset_bottom =  130
	_mut_panel.add_child(title)

	var sub := Label.new()
	sub.text = "Выбери одну из трёх"
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.offset_top    = 128
	sub.offset_left   = -200
	sub.offset_right  =  200
	sub.offset_bottom =  160
	_mut_panel.add_child(sub)

	$Root.add_child(_mut_panel)


func _on_mutation_available(options: Array) -> void:
	while _mut_panel.get_child_count() > 3:
		var old := _mut_panel.get_child(_mut_panel.get_child_count() - 1)
		_mut_panel.remove_child(old)
		old.queue_free()

	var card_w := 280
	var card_h := 180
	var gap    := 30
	var total_w := card_w * options.size() + gap * (options.size() - 1)
	var start_x := -total_w / 2

	for ci in options.size():
		var mid: int = options[ci]
		var card := Button.new()
		card.custom_minimum_size = Vector2(card_w, card_h)
		card.set_anchors_preset(Control.PRESET_CENTER)
		card.offset_left   = start_x + ci * (card_w + gap)
		card.offset_right  = start_x + ci * (card_w + gap) + card_w
		card.offset_top    = -card_h / 2 + 30
		card.offset_bottom =  card_h / 2 + 30

		var name_lbl := Label.new()
		name_lbl.text = Tuning.MUT_NAMES[mid]
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = Tuning.MUT_DESC[mid]
		desc_lbl.add_theme_font_size_override("font_size", 13)
		desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82))
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.set_anchors_preset(Control.PRESET_CENTER)
		desc_lbl.offset_left   = -120
		desc_lbl.offset_right  =  120
		desc_lbl.offset_top    =  30
		desc_lbl.offset_bottom =  120
		card.add_child(desc_lbl)

		card.pressed.connect(_on_mutation_chosen.bind(mid))
		_mut_panel.add_child(card)

	_mut_panel.visible = true


func _on_mutation_chosen(mid: int) -> void:
	sim.apply_mutation(mid)
	_mut_panel.visible = false


func _build_ticker() -> void:
	# Строка состояния: стопка коротких уведомлений вверху по центру.
	# Не затемняет экран, не ловит ввод, не ставит паузу.
	_ticker = VBoxContainer.new()
	_ticker.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_ticker.offset_left   = -320
	_ticker.offset_right  =  320
	_ticker.offset_top    =   12
	_ticker.alignment = BoxContainer.ALIGNMENT_CENTER
	_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticker.add_theme_constant_override("separation", 4)
	$Root.add_child(_ticker)


func _push_ticker(text: String, color: Color, dur: float) -> void:
	# Панелька с текстом; полупрозрачный фон только под строкой.
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.72)
	sb.set_content_margin_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", color)
	panel.add_child(lbl)

	_ticker.add_child(panel)
	_ticker_msgs.append({"ctrl": panel, "t": dur, "dur": dur})

	# Не больше 4 строк — старейшую убираем.
	while _ticker_msgs.size() > 4:
		var old: Dictionary = _ticker_msgs.pop_front()
		(old["ctrl"] as Control).queue_free()


func _on_escalation(level: int, headline: String) -> void:
	if level == -2:
		_push_ticker("★ СИНТЕЗ: %s" % headline, Color(0.4, 1.0, 0.65), Tuning.ESC_HEADLINE_DUR * 1.8)
	elif level == -1:
		_push_ticker("[!] %s" % headline, Color(1.0, 0.5, 0.1), Tuning.ESC_HEADLINE_DUR)
	else:
		_push_ticker("[ГАЗЕТА] %s" % headline, Color(1.0, 0.92, 0.3), Tuning.ESC_HEADLINE_DUR)


func _on_door_toggled(_floor: int, _di: int, is_open: bool) -> void:
	if is_open:
		_push_ticker("Дверь открыта", Color(0.7, 0.85, 1.0), 1.6)
	else:
		_push_ticker("Дверь закрыта", Color(1.0, 0.8, 0.5), 1.6)


func _build_grab_slider() -> void:
	const BAR_W := 360
	const BAR_H := 36
	_grab_panel = Control.new()
	_grab_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_grab_panel.offset_left   = -BAR_W / 2
	_grab_panel.offset_right  =  BAR_W / 2
	_grab_panel.offset_top    = -200
	_grab_panel.offset_bottom = -120
	_grab_panel.visible       = false

	# Фон
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.07, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.offset_top = -10; bg.offset_bottom = 40
	_grab_panel.add_child(bg)

	# Три зоны бара
	var zone_data := [
		[Color(0.70, 0.12, 0.12), "ВЫРВАЛСЯ"],
		[Color(0.12, 0.60, 0.18), "ЗАРАЗИЛСЯ"],
		[Color(0.35, 0.08, 0.50), "УБИТ"],
	]
	for zd in zone_data:
		var z := ColorRect.new()
		z.color = zd[0]
		z.size = Vector2(1, BAR_H)
		_grab_panel.add_child(z)
		_grab_zones.append(z)
		var lbl := Label.new()
		lbl.text = zd[1]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		z.add_child(lbl)

	# Курсор
	_grab_cursor = ColorRect.new()
	_grab_cursor.color    = Color(1, 1, 1, 0.95)
	_grab_cursor.size     = Vector2(4, BAR_H + 8)
	_grab_cursor.position = Vector2(BAR_W * 0.5 - 2, -4)
	_grab_panel.add_child(_grab_cursor)

	# Подсказка
	var hint := Label.new()
	hint.text = "ПРОБЕЛ — выбрать"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	hint.position = Vector2(0, BAR_H + 4)
	hint.size     = Vector2(BAR_W, 20)
	_grab_panel.add_child(hint)

	$Root.add_child(_grab_panel)
	_update_grab_zones(Tuning.ARCH_NORMAL, false)


func _update_grab_zones(arch: int, backstab: bool) -> void:
	const BAR_W := 360.0
	var bounds: Vector2 = sim.slider_bounds(arch, backstab)
	var edges := [0.0, bounds.x, bounds.y, 1.0]
	for i in 3:
		_grab_zones[i].position.x = edges[i] * BAR_W
		_grab_zones[i].size.x = (edges[i + 1] - edges[i]) * BAR_W


func _tick_ticker(delta: float) -> void:
	var i := _ticker_msgs.size() - 1
	while i >= 0:
		var m: Dictionary = _ticker_msgs[i]
		m["t"] -= delta
		var ctrl := m["ctrl"] as Control
		if m["t"] <= 0.0:
			ctrl.queue_free()
			_ticker_msgs.remove_at(i)
		else:
			ctrl.modulate.a = clampf(m["t"] / 0.6, 0.0, 1.0)   # плавное угасание
		i -= 1


func _process(delta: float) -> void:
	_tick_ticker(delta)

	# Шкала захвата
	var show_slider: bool = sim.finished == 0 and not _paused and sim.p_grab >= 0
	_grab_panel.visible = show_slider
	if show_slider and _grab_cursor:
		if _grab_zone_target != sim.p_grab:
			_grab_zone_target = sim.p_grab
			_update_grab_zones(sim.archetype[sim.p_grab], sim._backstab_applied)
		_grab_cursor.position.x = sim._slider_pos * 356.0 - 2.0
	else:
		_grab_zone_target = -1


func _on_finished(result: int, seconds: float) -> void:
	label.text = (
		"ГОРОД ПАЛ за %.0f сек" % seconds if result == 1
		else "УНИЧТОЖЕН — конец"
	)
	_mut_panel.visible = false
	_grab_panel.visible = false
	var revision := _run_revision
	await get_tree().create_timer(1.5, true, false, true).timeout
	if revision != _run_revision or sim.finished != result:
		return
	_build_story_text(result)
	_story_panel.visible = true
	_set_paused(true)
	$Root.move_child(_story_panel, -1)


func _build_story_panel() -> void:
	_story_panel = Control.new()
	_story_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_story_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_story_panel.visible = false

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.04, 0.06, 0.96)
	_story_panel.add_child(bg)

	var title := Label.new()
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top    = 20
	title.offset_bottom = 62
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.25, 0.15))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "ХРОНИКА ЗАРАЖЕНИЯ"
	_story_panel.add_child(title)

	_story_scroll = ScrollContainer.new()
	_story_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_story_scroll.offset_top    = 68
	_story_scroll.offset_bottom = -54
	_story_scroll.offset_left   = 40
	_story_scroll.offset_right  = -40
	_story_panel.add_child(_story_scroll)

	_story_text = RichTextLabel.new()
	_story_text.bbcode_enabled = true
	_story_text.fit_content    = true
	_story_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story_scroll.add_child(_story_text)

	var close_btn := Button.new()
	close_btn.text = "Закрыть  [R — рестарт]"
	close_btn.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	close_btn.offset_top    = -50
	close_btn.offset_bottom = -10
	close_btn.offset_left   = 300
	close_btn.offset_right  = -300
	close_btn.pressed.connect(func(): _story_panel.visible = false)
	_story_panel.add_child(close_btn)

	$Root.add_child(_story_panel)


func _g(d: Dictionary, m: String, f: String) -> String:
	return m if bool(d.get("male", true)) else f

func _cap(s: String) -> String:
	if s.is_empty(): return s
	return s[0].to_upper() + s.substr(1)

func _n_people(cnt: int) -> String:
	var m10 := cnt % 10
	var m100 := cnt % 100
	if m10 >= 2 and m10 <= 4 and not (m100 >= 12 and m100 <= 14):
		return "человека"
	return "человек"


func _build_story_text(result: int) -> void:
	var txt := ""
	var n: int = sim.pos.size()

	match result:
		1: txt += "[color=#e84040][b]▼ ГОРОД ПАЛ ▼[/b][/color]\n"
		2: txt += "[color=#e8a040][b]▼ УНИЧТОЖЕН ▼[/b][/color]\n"

	txt += "Время: [b]%.0f сек[/b] · Заражено: [b]%d[/b] из [b]%d[/b]\n\n" % [
		sim.elapsed, _count_infected(n), n
	]

	# --- Первая жертва ---
	var first_victim := _find_first_victim(n)
	if first_victim >= 0:
		var d: Dictionary = sim.identities[first_victim]
		var loc: String = Identity.LOCATIONS[randi() % Identity.LOCATIONS.size()]
		var tr  := str(d["trait"])
		txt += "[color=#ff6060][b]━━ ПЕРВАЯ ЖЕРТВА ━━[/b][/color]\n"
		txt += "[b]%s[/b], %s, %s.\n" % [Identity.full_name(d), Identity.age_str(d), d["occupation"]]
		var t0 := int(sim.infected_at[first_victim])
		match randi() % 4:
			0:
				txt += "%s %s — прямо %s, на %d-й секунде.\n" % [
					_g(d, "Схвачен", "Схвачена"), _g(d, "первым", "первой"), loc, t0
				]
				txt += "%s. %s.\n\n" % [_cap(tr), _g(d, "Кричал — никто не среагировал", "Кричала — никто не среагировал")]
			1:
				txt += "На %d-й секунде %s %s %s — и всё.\n" % [
					t0, _g(d, "он просто стоял", "она просто стояла"), loc, _g(d, "и зевал", "и зевала")
				]
				txt += "%s. Первый%s в хронике заражения.\n\n" % [_cap(tr), _g(d, "", "ая")]
			2:
				txt += "%s оказал%s не в то время и не в том месте.\n" % [
					_g(d, "Он", "Она"), _g(d, "ся", "ась")
				]
				txt += "%s. Заражён%s на %d-й секунде, %s.\n\n" % [
					_cap(tr), _g(d, "", "а"), t0, loc
				]
			_:
				txt += "Утром %s думал%s о работе. На %d-й секунде %s уже %s заражённым%s.\n" % [
					_g(d, "он", "она"), _g(d, "", "а"), t0,
					_g(d, "он", "она"), _g(d, "был", "была"), _g(d, "", "а")
				]
				txt += "%s. Первым%s.\n\n" % [_cap(tr), _g(d, "", "ой")]

	# --- Главный разносчик ---
	var spreader := _find_top_spreader(n)
	if spreader >= 0 and sim.spread_count[spreader] > 1:
		var d: Dictionary = sim.identities[spreader]
		var sc: int = sim.spread_count[spreader]
		var tr  := str(d["trait"])
		txt += "[color=#ff9030][b]━━ ГЛАВНЫЙ РАЗНОСЧИК ━━[/b][/color]\n"
		txt += "[b]%s[/b], %s.\n" % [Identity.full_name(d), d["occupation"]]
		match randi() % 3:
			0:
				txt += "%s — %s заразил%s ещё [b]%d[/b] %s.\n" % [
					_cap(tr), _g(d, "он", "она"), _g(d, "", "а"), sc, _n_people(sc)
				]
				txt += "%s %s сам%s того не заметил%s.\n\n" % [
					_g(d, "Просто ходил", "Просто ходила"), _g(d, "и", "и"),
					_g(d, "", "а"), _g(d, "", "а")
				]
			1:
				txt += "За один забег %s распростран%s вирус на [b]%d[/b] %s.\n" % [
					_g(d, "он", "она"), _g(d, "ил", "ила"), sc, _n_people(sc)
				]
				txt += "%s. Рекордсмен%s.\n\n" % [_cap(tr), _g(d, "", "ка")]
			_:
				txt += "[b]%d[/b] %s — столько %s успел%s заразить, пока не вскрылс%s.\n" % [
					sc, _n_people(sc), _g(d, "он", "она"), _g(d, "", "а"), _g(d, "я", "ась")
				]
				txt += "%s. Невольный чемпион.\n\n" % _cap(tr)

	# --- Обращённые ---
	txt += "[color=#6090ff][b]━━ ОБРАЩЁННЫЕ СТРАЖИ ПОРЯДКА ━━[/b][/color]\n"
	var cop_shown := 0
	for i in n:
		if sim.was_cop[i] == 1 and sim.state[i] != 0:
			var d: Dictionary = sim.identities[i]
			var sc: int = sim.spread_count[i]
			var lines := [
				"Офицер [b]%s[/b] принял%s другую сторону. Заразил%s %d %s после обращения." % [
					Identity.full_name(d), _g(d, "", "а"), _g(d, "", "а"), sc, _n_people(sc)
				],
				"Офицер [b]%s[/b]: с утра патрулировал, к вечеру — сам%s источник. [b]%d[/b] заражён%s." % [
					Identity.full_name(d), _g(d, "", "а"), sc, _g(d, "о", "о")
				],
				"[b]%s[/b] не устоял%s. Бывший страж порядка, %d новых жертв." % [
					Identity.full_name(d), _g(d, "", "а"), sc
				],
			]
			txt += lines[randi() % lines.size()] + "\n"
			cop_shown += 1
			if cop_shown >= 5:
				break
	if cop_shown == 0:
		txt += "Ни один офицер не был обращён — повезло им.\n"
	txt += "\n"

	# --- Хроника выживших и заражённых ---
	txt += "[color=#aaaaaa][b]━━ ЧТО СТАЛО С ОСТАЛЬНЫМИ ━━[/b][/color]\n"
	var shown := 0
	var indices := range(n)
	indices.shuffle()
	for i in indices:
		if shown >= 8:
			break
		var d: Dictionary = sim.identities[i]
		var tr  := str(d["trait"])
		var nm  := Identity.full_name(d)
		var occ := str(d["occupation"])

		if sim.state[i] == 0:
			var lines := [
				"[color=#40e880][b]%s[/b], %s — выжил%s. Остал%s цел%s. %s.[/color]" % [
					nm, occ, _g(d, "", "а"), _g(d, "ся", "ась"), _g(d, "", "а"), _cap(tr)
				],
				"[color=#40e880][b]%s[/b], %s. %s. Остал%s в живых — сам%s не верит.[/color]" % [
					nm, occ, _cap(tr), _g(d, "ся", "ась"), _g(d, "", "а")
				],
				"[color=#40e880][b]%s[/b], %s — жив%s. %s. Будет рассказывать внукам.[/color]" % [
					nm, occ, _g(d, "", "а"), _cap(tr)
				],
			]
			txt += lines[randi() % lines.size()] + "\n"
			shown += 1
		elif sim.state[i] in [1, 2, 4, 5]:
			if sim.infected_by[i] == -1:
				var loc: String = Identity.LOCATIONS[randi() % Identity.LOCATIONS.size()]
				var lines := [
					"[b]%s[/b], %s. Пойман%s игроком %s. %s. Кричал%s — поздно." % [
						nm, occ, _g(d, "", "а"), loc, _cap(tr), _g(d, "", "а")
					],
					"[b]%s[/b], %s. %s. %s оказал%s %s — и попал%s прямо в руки." % [
						nm, occ, _cap(tr), _g(d, "Он", "Она"), _g(d, "ся", "ась"), loc, _g(d, "", "а")
					],
					"[b]%s[/b], %s. Схвачен%s %s. Успел%s подумать: «%s»." % [
						nm, occ, _g(d, "", "а"), loc, _g(d, "", "а"), tr
					],
				]
				txt += lines[randi() % lines.size()] + "\n"
			elif sim.infected_by[i] >= 0:
				var inf_d: Dictionary = sim.identities[sim.infected_by[i]]
				var inf_nm := Identity.full_name(inf_d)
				var lines := [
					"[b]%s[/b], %s. Заражён%s через [b]%s[/b] — %s просто прошёл%s мимо. %s." % [
						nm, occ, _g(d, "", "а"), inf_nm,
						_g(inf_d, "тот", "та"), _g(inf_d, "", "ла"), _cap(tr)
					],
					"[b]%s[/b], %s. %s. [b]%s[/b] %s — и цепочка дотянулась." % [
						nm, occ, _cap(tr), inf_nm,
						_g(inf_d, "прошёл рядом", "прошла рядом")
					],
					"[b]%s[/b], %s. Не повезло оказаться рядом с [b]%s[/b]. %s." % [
						nm, occ, inf_nm, _cap(tr)
					],
				]
				txt += lines[randi() % lines.size()] + "\n"
			else:
				var lines := [
					"[b]%s[/b], %s. Заражён%s — как именно, уже не узнать. %s." % [
						nm, occ, _g(d, "", "а"), _cap(tr)
					],
					"[b]%s[/b], %s. %s. Подхватил%s вирус где-то в толпе." % [
						nm, occ, _cap(tr), _g(d, "", "а")
					],
				]
				txt += lines[randi() % lines.size()] + "\n"
			shown += 1

	_story_text.text = txt


func _count_infected(n: int) -> int:
	var c := 0
	for i in n:
		if sim.infected_by[i] != -3:
			c += 1
	return c


func _find_first_victim(n: int) -> int:
	var best   := -1
	var best_t := INF
	for i in n:
		if sim.infected_by[i] != -3 and sim.infected_at[i] < best_t:
			best_t = sim.infected_at[i]
			best   = i
	return best


func _find_top_spreader(n: int) -> int:
	var best   := -1
	var best_c := 0
	for i in n:
		if sim.spread_count[i] > best_c:
			best_c = sim.spread_count[i]
			best   = i
	return best
