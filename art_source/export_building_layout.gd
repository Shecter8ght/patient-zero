extends SceneTree
func _initialize() -> void:
	call_deferred("export_layout")
func export_layout() -> void:
	var map = root.get_node("MapGen")
	map.generate()
	var entries: Array = []
	for entry in map.building_data:
		if entry["is_mall"] or is_equal_approx(entry["height"], Tuning.FLOOR_HEIGHT):
			continue
		var kind := "utility" if is_equal_approx(entry["height"], 2 * Tuning.FLOOR_HEIGHT) else ("office" if entry["color"].b > 0.6 else "apartment")
		entries.append({"id": "building_%s_%d" % [kind, entry["floor_id"]], "kind": kind, "width": entry["rect"].size.x, "depth": entry["rect"].size.y, "height": entry["height"], "floor_id": entry["floor_id"]})
	FileAccess.open("res://art_source/building_layout.json", FileAccess.WRITE).store_string(JSON.stringify(entries, "  "))
	print("Exported building layout: ", entries.size())
	quit()
