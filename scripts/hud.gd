extends CanvasLayer

@export var sim_path: NodePath
var sim: Node3D
var bar:       ProgressBar
var label:     Label
var qte_bg:    Panel     # подложка за QTE-клавишей
var qte_label: Label     # большая клавиша (арест или захват)
var _menu:     Control   # меню паузы
var _mut_panel: Control  # панель выбора мутации
var _headline_panel: Control
var _headline_label: Label
var _headline_timer := 0.0
var _paused    := false

var _story_panel:  Control
var _story_scroll: ScrollContainer
var _story_text:   RichTextLabel


func _ready() -> void:
	sim   = get_node(sim_path)
	bar   = $Root/Suspicion
	label = $Root/Status

	# Подложка QTE
	qte_bg = Panel.new()
	qte_bg.set_anchors_preset(Control.PRESET_CENTER)
	qte_bg.offset_left   = -60
	qte_bg.offset_right  =  60
	qte_bg.offset_top    = -55
	qte_bg.offset_bottom =  55
	qte_bg.visible = false
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.08, 0.82)
	bg_style.corner_radius_top_left     = 8
	bg_style.corner_radius_top_right    = 8
	bg_style.corner_radius_bottom_left  = 8
	bg_style.corner_radius_bottom_right = 8
	qte_bg.add_theme_stylebox_override("panel", bg_style)
	$Root.add_child(qte_bg)

	# QTE-клавиша поверх подложки
	qte_label = Label.new()
	qte_label.add_theme_font_size_override("font_size", 72)
	qte_label.add_theme_color_override("font_color", Color(1.0, 0.18, 0.18))
	qte_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qte_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	qte_label.set_anchors_preset(Control.PRESET_CENTER)
	qte_label.offset_left   = -60
	qte_label.offset_right  =  60
	qte_label.offset_top    = -55
	qte_label.offset_bottom =  55
	qte_label.visible = false
	$Root.add_child(qte_label)

	_build_menu()
	_build_mut_panel()
	_build_headline_panel()
	_build_story_panel()

	sim.stats_changed.connect(_on_stats)
	sim.run_finished.connect(_on_finished)
	sim.mutation_available.connect(_on_mutation_available)
	sim.escalation_triggered.connect(_on_escalation)


func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.visible = false

	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	_menu.add_child(overlay)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left   = -100
	box.offset_right  =  100
	box.offset_top    =  -60
	box.offset_bottom =   60
	box.add_theme_constant_override("separation", 16)
	_menu.add_child(box)

	var title := Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	var btn := Button.new()
	btn.text = "Перезапустить"
	btn.pressed.connect(_on_restart_pressed)
	box.add_child(btn)

	$Root.add_child(_menu)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_paused = not _paused
		_menu.visible = _paused
		Engine.time_scale = 0.0 if _paused else 1.0
		get_viewport().set_input_as_handled()


func _on_restart_pressed() -> void:
	_paused = false
	_menu.visible = false
	Engine.time_scale = 1.0
	sim.reset_run()


func _on_stats(healthy: int, infected: int, latent: int, dead: int,
		cops: int, suspicion: float, arrest_prog: float, qte_key: String, evac_count: int) -> void:

	if arrest_prog > 0.0:
		bar.value = arrest_prog * 100.0
		var hits_left := ceili((1.0 - sim.p_prog) / Tuning.QTE_HIT_PROG)
		label.text = "ЗАДЕРЖАНИЕ   ещё нажатий: %d   (%.1f сек)   [ПРОБЕЛ — вырваться]" % [
			hits_left, (1.0 - arrest_prog) * Tuning.ARREST_TIME
		]
		var st := bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
		if st:
			st.bg_color = Color(0.92, 0.15, 0.15)
			bar.add_theme_stylebox_override("fill", st)

		qte_label.text    = qte_key
		qte_label.visible = qte_key != ""
		qte_bg.visible    = qte_key != ""
	else:
		qte_label.visible = false
		qte_bg.visible    = false

		# Захват — показываем QTE клавишу в другом цвете
		if qte_key != "":
			qte_label.add_theme_color_override("font_color", Color(1.0, 0.80, 0.10))
			qte_label.text    = qte_key
			qte_label.visible = true
			qte_bg.visible    = true
		else:
			qte_label.add_theme_color_override("font_color", Color(1.0, 0.18, 0.18))

		bar.value = suspicion

		var total := healthy + infected + dead
		var pct   := 0
		if total > 0:
			pct = roundi(float(infected + dead) / float(total) * 100.0)
		var evac_left := Tuning.EVAC_LOSE_AT - evac_count
		var evac_warn := "(!)" if evac_count > Tuning.EVAC_LOSE_AT * 0.6 else ""
		var horde_str := ""
		if sim.horde_target_life > 0.0:
			horde_str = "\n> ОРДА — цель (%.0f сек)" % sim.horde_target_life
		label.text = (
			"Заражено: %d%%   Здоровых: %d   Инкуб: %d\n" +
			"Мертвых: %d   Полиции: %d   Подозрение: %d\n" +
			"Эвакуировалось: %d / %d %s\n" +
			"ЛКМ — захват   ПКМ — орда   Alt+Sprint — бросок   Esc — пауза"
		) % [pct, healthy, latent, dead, cops, roundi(suspicion),
			evac_count, Tuning.EVAC_LOSE_AT, evac_warn] + horde_str

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
		_mut_panel.get_child(_mut_panel.get_child_count() - 1).queue_free()

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


func _build_headline_panel() -> void:
	_headline_panel = Control.new()
	_headline_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_headline_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_headline_panel.visible = false

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.04, 0.04, 0.88)
	_headline_panel.add_child(bg)

	_headline_label = Label.new()
	_headline_label.set_anchors_preset(Control.PRESET_CENTER)
	_headline_label.offset_left   = -420
	_headline_label.offset_right  =  420
	_headline_label.offset_top    =  -44
	_headline_label.offset_bottom =   44
	_headline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_headline_label.add_theme_font_size_override("font_size", 28)
	_headline_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.3))
	_headline_panel.add_child(_headline_label)

	$Root.add_child(_headline_panel)


func _on_escalation(level: int, headline: String) -> void:
	_headline_label.text = "[ГАЗЕТА]  %s" % headline
	_headline_panel.visible = true
	_headline_timer = Tuning.ESC_HEADLINE_DUR


func _process(delta: float) -> void:
	if _headline_timer > 0.0:
		_headline_timer -= delta
		if _headline_timer <= 0.0:
			_headline_panel.visible = false


func _on_finished(result: int, seconds: float) -> void:
	qte_label.visible = false
	qte_bg.visible    = false
	label.text = (
		"ГОРОД ПАЛ за %.0f сек" % seconds if result == 1
		else ("ЭВАКУАЦИЯ — слишком много сбежало" if result == 3
		else "ВЫЧИСЛЕН — конец")
	)
	await get_tree().create_timer(1.5).timeout
	_build_story_text(result)
	_story_panel.visible = true
	_menu.visible        = true


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
		2: txt += "[color=#e8a040][b]▼ ВЫЧИСЛЕН ▼[/b][/color]\n"
		_: txt += "[color=#40e880][b]▼ ЭВАКУАЦИЯ УДАЛАСЬ ▼[/b][/color]\n"

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
				"[color=#40e880][b]%s[/b], %s — выжил%s. Уехал%s первым%s автобусом. %s.[/color]" % [
					nm, occ, _g(d, "", "а"), _g(d, "", "а"), _g(d, "", "ым"), _cap(tr)
				],
				"[color=#40e880][b]%s[/b], %s. %s. Добрался%s до эвакуации — сам%s не верит.[/color]" % [
					nm, occ, _cap(tr), _g(d, "", "ась"), _g(d, "", "а")
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
		if sim.state[i] != 0:   # 0 = HEALTHY
			c += 1
	return c


func _find_first_victim(n: int) -> int:
	var best   := -1
	var best_t := INF
	for i in n:
		if sim.infected_at[i] > 0.0 and sim.infected_at[i] < best_t:
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
