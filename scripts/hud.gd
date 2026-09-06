extends CanvasLayer

@export var sim_path: NodePath
var sim: Node3D
var bar:       ProgressBar
var label:     Label
var qte_bg:    Panel     # подложка за QTE-клавишей
var qte_label: Label     # большая клавиша (арест или захват)
var _menu:     Control   # меню паузы
var _mut_panel: Control  # панель выбора мутации
var _paused    := false


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

	sim.stats_changed.connect(_on_stats)
	sim.run_finished.connect(_on_finished)
	sim.mutation_available.connect(_on_mutation_available)


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


func _on_finished(result: int, seconds: float) -> void:
	qte_label.visible = false
	qte_bg.visible    = false
	label.text = (
		"ГОРОД ПАЛ за %.0f сек" % seconds if result == 1
		else ("ЭВАКУАЦИЯ — слишком много сбежало" if result == 3
		else "ВЫЧИСЛЕН — конец")
	)
