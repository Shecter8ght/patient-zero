extends CanvasLayer

@export var sim_path: NodePath
var sim: Node3D
var bar:       ProgressBar
var label:     Label
var qte_bg:    Panel     # подложка за QTE-клавишей
var qte_label: Label     # большая клавиша (арест или захват)
var _menu:     Control   # меню паузы
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

	sim.stats_changed.connect(_on_stats)
	sim.run_finished.connect(_on_finished)


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
		label.text = (
			"Заражено: %d%%   Здоровых: %d   Инкуб: %d\n" +
			"Мертвых: %d   Полиции: %d   Подозрение: %d\n" +
			"Эвакуировалось: %d / %d %s\n" +
			"ЛКМ — захват   Alt+Sprint — бросок   Esc — пауза"
		) % [pct, healthy, latent, dead, cops, roundi(suspicion),
			evac_count, Tuning.EVAC_LOSE_AT, evac_warn]

		var st := bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
		if st:
			st.bg_color = (
				Color(0.89, 0.29, 0.29) if suspicion > 70.0
				else (Color(0.94, 0.62, 0.15) if suspicion > 35.0
				else Color(0.39, 0.60, 0.13))
			)
			bar.add_theme_stylebox_override("fill", st)


func _on_finished(result: int, seconds: float) -> void:
	qte_label.visible = false
	qte_bg.visible    = false
	label.text = (
		"ГОРОД ПАЛ за %.0f сек" % seconds if result == 1
		else ("ЭВАКУАЦИЯ — слишком много сбежало" if result == 3
		else "ВЫЧИСЛЕН — конец")
	)
