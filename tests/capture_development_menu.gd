extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var hud = game.get_node("HUD")
	DirAccess.make_dir_recursive_absolute("res://tests/output")
	for frame in 12: await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/output/gameplay.png")
	hud._set_paused(true)
	var tabs: TabContainer = hud._dev_menu._tabs
	for tab in 3:
		tabs.current_tab = tab
		for frame in 4: await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/output/menu_%d.png" % tab)
		if tab > 0:
			var scroll := tabs.get_child(tab) as ScrollContainer
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
			for frame in 4: await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tests/output/menu_%d_bottom.png" % tab)
	tabs.current_tab = 2
	var roadmap := tabs.get_child(2) as ScrollContainer
	roadmap.scroll_vertical = 0
	var grid := roadmap.find_child("CategoryGrid", true, false) as GridContainer
	for card in grid.get_children():
		(card.get_child(0).get_child(0) as Button).button_pressed = true
	for frame in 4: await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/output/roadmap_expanded.png")
	root.size = Vector2i(960, 540)
	for frame in 4: await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/output/menu_small.png")
	hud._set_paused(false)
	print("DEVELOPMENT_MENU_CAPTURE_COMPLETE")
	quit()
