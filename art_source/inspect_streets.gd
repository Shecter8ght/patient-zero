extends SceneTree
func _initialize() -> void: call_deferred("inspect")
func inspect() -> void:
	var map=root.get_node("MapGen")
	map.generate()
	for entry in map.building_data:
		print(entry["floor_id"], " ", entry["rect"])
	for p in [Vector2(0,-62),Vector2(62,0),Vector2(0,62),Vector2(-62,0)]:
		print("EVAC ", p, " blocked ",map.is_blocked(p,2.5,0))
	quit()
