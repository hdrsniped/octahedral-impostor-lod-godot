extends SceneTree

var _rows: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


# --- Fitted card measurement ---
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var settings := OctaBakeSettings.new()

	var main: Array[Node3D] = [DemoObjects.rock(), DemoObjects.tree(), DemoObjects.rings(), DemoObjects.textured()]
	for o in main:
		world.add_child(o)
	var atlas := await OctaBaker.bake(main, root, settings)
	_collect("", atlas, "main atlas")
	print("INFO main atlas: %d objects, frame %d px, grid %d, frame_scale %.3f" % [atlas.object_count(), atlas.frame_resolution, atlas.grid_size, atlas.frame_scale])

	var split_settings := OctaBakeSettings.new()
	split_settings.split_parts = true
	var rings := DemoObjects.rings()
	world.add_child(rings)
	var parts := OctaLOD.split_parts([rings])
	var split_atlas := await OctaBaker.bake(parts, root, split_settings)
	_collect("rings part ", split_atlas, "split parts")

	var group: Array[Node3D] = []
	for i in 3:
		var r := DemoObjects.rock(i + 1)
		r.name = "Rock%d" % (i + 1)
		world.add_child(r)
		group.append(r)
	var group_atlas := await OctaBaker.bake(group, root, settings)
	_collect("joined ", group_atlas, "joined group")

	_print_table()
	var gate := 0
	for r in _rows:
		if r.name in ["Rock", "Tree", "Rings"] and 1.0 - r.poly8 > 0.25:
			gate += 1
	print("GATE 8-gon saves more than 25%% of the quad on %d of 3 (rock, tree, rings): %s" % [gate, "BUILD in v2.2" if gate >= 2 else "DO NOT build"])
	print("RESULT PASS (0 failures)")
	for c in root.get_children():
		c.queue_free()
	await process_frame
	quit(0)


func _collect(prefix: String, atlas: OctaAtlas, group: String) -> void:
	for i in atlas.object_count():
		var c := atlas.card_coverage(i)
		c.name = prefix + (str(i + 1) if atlas.object_names[i].begins_with("@") else atlas.object_names[i])
		c.group = group
		_rows.append(c)


func _print_table() -> void:
	print("COVERAGE (all numbers are %% of the card quad = the bounding-sphere square; views = every baked view of the object, hemisphere)")
	print("COVERAGE %-18s %8s %7s %7s %7s %7s %9s %10s %10s %12s" % ["object", "union %", "rect %", "hull %", "8-gon %", "6-gon %", "mean view %", "8-gon saved", "6-gon saved", "ideal saved"])
	for r in _rows:
		var ideal: float = 1.0 - r.mean_view
		print("COVERAGE %-18s %8.1f %7.1f %7.1f %7.1f %7.1f %9.1f %10.1f %10.1f %12.1f   (8-gon captures %.0f%% of ideal)" % [
			r.name, r.union * 100.0, r.rect * 100.0, r.hull * 100.0, r.poly8 * 100.0, r.poly6 * 100.0, r.mean_view * 100.0,
			(1.0 - r.poly8) * 100.0, (1.0 - r.poly6) * 100.0, ideal * 100.0, (1.0 - r.poly8) / maxf(ideal, 1e-6) * 100.0])
