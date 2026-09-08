extends Control
## Shared development checklist. Acceptance is independent from implementation.
signal resume_requested
signal restart_requested

const PLAN_PATH := "res://data/development_plan.json"
const EXPORTED_ACCEPTANCE_PATH := "user://development_acceptance.json"
var _tabs: TabContainer
var _notice: Label
var _save: Button
var _pending: Dictionary = {}
var _checks: Dictionary = {}
var _expanded_categories: Dictionary = {}
var _category_bodies: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var overlay := ColorRect.new()
	overlay.color = Color(0.025, 0.035, 0.045, 1.0)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = "PATIENT ZERO  /  ПАУЗА"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	var game := VBoxContainer.new()
	game.name = "Игра"
	game.add_theme_constant_override("separation", 18)
	_tabs.add_child(game)
	_add_label(game, "Заразить город", 26)
	_add_label(game, "Победа: охват %d%% населения — заражённые (включая людей без симптомов) и погибшие. Каждый учитывается один раз.\nПоражение: смерть игрока от огня полиции. Эвакуации, ареста и лимита времени нет." % roundi(Tuning.WIN_RATIO * 100.0), 18)
	_add_label(game, "WASD — движение   •   Shift — бег\nЛКМ удерживать — захват   •   Space — остановить шкалу\nПКМ — движение или атака орды   •   F — следовать   •   H — удерживать\nAlt на бегу — бросок к цели\nR — новый забег   •   Esc — открыть или закрыть меню", 18)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	box.add_child(footer)
	var resume := Button.new()
	resume.text = "Вернуться в игру"
	resume.custom_minimum_size.y = 42
	resume.pressed.connect(func(): resume_requested.emit())
	footer.add_child(resume)
	var restart := Button.new()
	restart.text = "Новый забег"
	restart.pressed.connect(func(): restart_requested.emit())
	footer.add_child(restart)
	_save = Button.new()
	_save.text = "Сохранить отметки"
	_save.disabled = true
	_save.pressed.connect(_save_acceptance)
	footer.add_child(_save)
	_notice = Label.new()
	_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_notice)
	refresh()


func _add_label(parent: Node, text: String, font_size: int) -> Label:
	var item := Label.new()
	item.text = text
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.add_theme_font_size_override("font_size", font_size)
	parent.add_child(item)
	return item


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func refresh() -> void:
	if _tabs == null:
		return
	var selected := _tabs.current_tab
	while _tabs.get_child_count() > 1:
		var old := _tabs.get_child(1)
		_tabs.remove_child(old)
		old.queue_free()
	_checks.clear()
	_category_bodies.clear()
	var plan := _read_json(PLAN_PATH)
	var local := _read_json(EXPORTED_ACCEPTANCE_PATH) if not OS.has_feature("editor") else {}
	for section in ["reworks", "roadmap"]:
		var scroll := ScrollContainer.new()
		scroll.name = "Переделки" if section == "reworks" else "Дорожная карта"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_tabs.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 14)
		scroll.add_child(list)
		_add_label(list, "Галочка означает «проверено и принято». Статус «Реализовано» сам по себе не является приёмкой. Отметки сохраняются отдельно от забега.", 16)
		if section == "roadmap":
			_add_label(list, "Нажмите на категорию, чтобы раскрыть пункты. «Идеи» — кандидаты для обсуждения, а не обещанные функции.", 15)
		else:
			_add_label(list, "Нажмите на категорию, чтобы раскрыть пункты. Статус пункта показан отдельно от галочки приёмки.", 15)
		_build_category_grid(list, plan.get(section, []), local)
	_tabs.current_tab = clampi(selected, 0, _tabs.get_tab_count() - 1)
	if plan.is_empty():
		_notice.text = "Не удалось загрузить план разработки."
	elif _pending.is_empty():
		_notice.text = "Отмечайте только после проверки."


func _build_category_grid(parent: Control, entries: Array, local: Dictionary) -> void:
	var groups: Dictionary = {}
	for entry: Dictionary in entries:
		var phase := str(entry.get("phase", "Без категории"))
		if not groups.has(phase):
			groups[phase] = []
		groups[phase].append(entry)
	var grid := GridContainer.new()
	grid.name = "CategoryGrid"
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	parent.add_child(grid)
	for phase: String in groups:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var style := StyleBoxFlat.new()
		style.bg_color = Color("15232c")
		style.border_color = Color("395563")
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(10)
		card.add_theme_stylebox_override("panel", style)
		grid.add_child(card)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 12)
		card.add_child(column)
		var header := Button.new()
		header.custom_minimum_size.y = 108
		header.toggle_mode = true
		header.button_pressed = bool(_expanded_categories.get(phase, false))
		header.tooltip_text = phase
		column.add_child(header)
		var caption := VBoxContainer.new()
		caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		caption.offset_left = 10
		caption.offset_right = -10
		caption.offset_top = 8
		caption.offset_bottom = -8
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(caption)
		var title := _add_label(caption, phase.replace("  ", "\n"), 16)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var hint := _add_label(caption, "", 13)
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint.modulate = Color("b4d8e8")
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 16)
		column.add_child(body)
		_category_bodies[phase] = body
		var count: int = groups[phase].size()
		_set_category_expanded(header.button_pressed, phase, body, hint, count)
		header.toggled.connect(_set_category_expanded.bind(phase, body, hint, count))
		for entry: Dictionary in groups[phase]:
			var id := str(entry["id"])
			var task := VBoxContainer.new()
			task.add_theme_constant_override("separation", 6)
			body.add_child(task)
			var line := HBoxContainer.new()
			task.add_child(line)
			var check := CheckBox.new()
			check.custom_minimum_size = Vector2(28, 28)
			check.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			check.add_theme_icon_override("unchecked", _checkbox_icon(false))
			check.add_theme_icon_override("checked", _checkbox_icon(true))
			check.tooltip_text = "Проверено и принято: " + str(entry["title"])
			check.button_pressed = bool(_pending.get(id, local.get(id, entry.get("accepted", false))))
			line.add_child(check)
			_checks[id] = check
			_add_label(line, str(entry["title"]), 15)
			var status_text := str(entry.get("status", "Запланировано"))
			var status := _add_label(task, "● " + status_text, 13)
			status.modulate = _status_color(status_text)
			_add_label(task, str(entry["description"]), 14)
			var acceptance := _add_label(task, "Приёмка: " + str(entry["acceptance"]), 13)
			acceptance.modulate = Color("bac7ce")
			check.toggled.connect(_mark_acceptance.bind(id))


## Цвет статуса: запланировано → реализовано → принято (визуальная ротация).
func _status_color(status: String) -> Color:
	var s := status.to_lower()
	if s.contains("принят"):
		return Color("6bd88a")   # зелёный — принято пользователем
	elif s.contains("реализ") or s.contains("выполн") or s.contains("готов"):
		return Color("e8d06b")   # жёлтый — реализовано, ждёт приёмки
	elif s.contains("иде"):
		return Color("b48ce8")   # фиолетовый — идея
	return Color("8fb4c8")       # синий — запланировано


func _set_category_expanded(expanded: bool, phase: String, body: Control, hint: Label, count: int) -> void:
	_expanded_categories[phase] = expanded
	body.visible = expanded
	hint.text = "%s  ·  Пунктов: %d" % ["− Свернуть" if expanded else "+ Раскрыть", count]


func _mark_acceptance(value: bool, id: String) -> void:
	_pending[id] = value
	_save.disabled = false
	_notice.text = "Есть несохранённые отметки."


func _save_acceptance() -> void:
	# Reload first so edits made by another developer are preserved.
	var plan := _read_json(PLAN_PATH)
	if plan.is_empty():
		_notice.text = "План недоступен. Отметки не сохранены."
		return
	var path := PLAN_PATH
	var output := plan
	if not OS.has_feature("editor"):
		path = EXPORTED_ACCEPTANCE_PATH
		output = _read_json(path)
		output.merge(_pending, true)
	else:
		for section in ["reworks", "roadmap"]:
			for entry: Dictionary in output.get(section, []):
				if _pending.has(str(entry["id"])):
					entry["accepted"] = _pending[str(entry["id"])]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_notice.text = "Не удалось сохранить отметки. Проверьте доступ к файлу."
		return
	file.store_string(JSON.stringify(output, "\t", false) + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		_notice.text = "Ошибка записи. Отметки пока не сохранены."
		return
	_pending.clear()
	_save.disabled = true
	_notice.text = "Отметки сохранены."


func _checkbox_icon(checked: bool) -> Texture2D:
	var mark := '<path d="M6 12l4 4 8-9" fill="none" stroke="#b5efc8" stroke-width="2.5"/>' if checked else ""
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect x="2" y="2" width="20" height="20" rx="3" fill="#15232c" stroke="#b4cbd7" stroke-width="2"/>%s</svg>' % mark
	var bitmap := Image.new()
	bitmap.load_svg_from_string(svg)
	return ImageTexture.create_from_image(bitmap)
