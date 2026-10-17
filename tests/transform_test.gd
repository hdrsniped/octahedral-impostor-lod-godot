extends SceneTree

const VIEWS := [Vector3(10, 0, 3.5), Vector3(30, 80, 3.5), Vector3(55, 150, 3.5), Vector3(20, 230, 3.5), Vector3(70, 300, 6.0), Vector3(-25, 40, 4.0)]
const CASES := {
	"identity": [Vector3.ONE, Vector3.ZERO],
	"uniform scale": [Vector3(2.5, 2.5, 2.5), Vector3.ZERO],
	"non-uniform scale": [Vector3(1.6, 0.6, 2.2), Vector3.ZERO],
	"rotated": [Vector3.ONE, Vector3(30, 110, 20)],
	"non-uniform scale and rotation": [Vector3(1.4, 0.7, 2.0), Vector3(25, 70, 35)],
}
const MAX_IOU_DROP := 0.03
const MAX_MAE_RISE := 3.0
const MAX_BAD_RISE := 3.0

var _fails := 0
var _world: Node3D
var _atlas: OctaAtlas


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


# --- Scaled and rotated sources bake and match the real mesh ---
func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var s := OctaBakeSettings.new()
	s.max_atlas_size = 1024
	s.hemisphere = false
	var objects := {"Rock": DemoObjects.rock(3), "Tree": DemoObjects.tree()}
	for oname in objects:
		var src: Node3D = objects[oname]
		_world.add_child(src)
		var plain := await OctaBaker.bake([src], root, s)
		var ref := {}
		for cname in CASES:
			var place := _place(CASES[cname][0], CASES[cname][1])
			src.transform = place
			var atlas := await OctaBaker.bake([src], root, s)
			src.transform = Transform3D.IDENTITY
			_check(atlas.bounds[0].is_equal_approx(plain.bounds[0]), "%s %s: baking the transformed source gives the same local bounds (%s vs %s)" % [oname, cname, atlas.bounds[0], plain.bounds[0]])
			for q in [OctaAtlas.Quality.HIGH, OctaAtlas.Quality.ULTRA]:
				for mode in ["self", "parent"]:
					_atlas = atlas if mode == "self" else plain
					var r := await _measure(src, q, place, mode == "parent")
					var label := "%s %s %s (%s transform)" % [oname, "high" if q == OctaAtlas.Quality.HIGH else "ultra", cname, mode]
					var key := "%s%d%s" % [oname, q, mode]
					if cname == "identity":
						ref[key] = r
						print("REF %s IoU %.3f MAE %.1f bad %.1f%%" % [label, r.iou, r.mae, r.bad])
						continue
					var base: Dictionary = ref[key]
					_check(r.iou > base.iou - MAX_IOU_DROP and r.mae < base.mae + MAX_MAE_RISE and r.bad < base.bad + MAX_BAD_RISE,
							"%s: IoU %.3f (ref %.3f), MAE %.1f (ref %.1f), bad %.1f%% (ref %.1f%%)" % [label, r.iou, base.iou, r.mae, base.mae, r.bad, base.bad])
		_atlas = plain
		var qref := {}
		for cname in CASES:
			src.transform = _place(CASES[cname][0], CASES[cname][1])
			var card := _atlas.create_card(0, OctaAtlas.Quality.HIGH)
			src.add_child(card)
			card.set_meta(OctaLOD.SOURCE_META, card.get_path_to(src))
			var qm: Dictionary = await OctaQuality.measure(src, root)
			card.free()
			if cname == "identity":
				qref = qm
				continue
			_check(not qm.has("error") and absf(qm.iou - qref.iou) < MAX_IOU_DROP and qm.bad_pct < qref.bad_pct + MAX_BAD_RISE,
					"%s %s Check Quality: match %.3f (ref %.3f), wrong %.1f%% (ref %.1f%%)" % [oname, cname, qm.get("iou", 0.0), qref.iou, qm.get("bad_pct", 100.0), qref.bad_pct])
		src.transform = Transform3D.IDENTITY
		src.free()
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	for c in root.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	quit(1 if _fails else 0)


func _place(scale: Vector3, euler_deg: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(euler_deg * PI / 180.0).scaled_local(scale), Vector3(2, 0.5, -3))


func _measure(src: Node3D, quality: int, place: Transform3D, via_parent: bool) -> Dictionary:
	var b: Vector4 = OctaBaker._collect(src).bounds
	var basis := place.basis
	var real := TestRig.make(root)
	var fake := TestRig.make(root)
	var holder := Node3D.new()
	var card := _atlas.create_card(0, quality)
	var parent := src.get_parent()
	parent.remove_child(src)
	if via_parent:
		holder.transform = place
		holder.add_child(src)
		var c2 := Node3D.new()
		c2.add_child(card)
		fake.world.add_child(c2)
		c2.transform = place
		real.world.add_child(holder)
	else:
		src.transform = place
		real.world.add_child(src)
		card.transform = _atlas.card_transform(src)
		fake.world.add_child(card)
	var local_center := Vector3(b.x, b.y, b.z)
	var center := place * local_center
	var radius := b.w * maxf(basis.get_scale().x, maxf(basis.get_scale().y, basis.get_scale().z))
	var acc := {iou = 0.0, mae = 0.0, bad = 0.0}
	for v: Vector3 in VIEWS:
		var e := deg_to_rad(v.x)
		var az := deg_to_rad(v.y)
		var dir := Vector3(cos(e) * sin(az), sin(e), cos(e) * cos(az))
		for rig in [real, fake]:
			TestRig.shoot(rig, center + dir * radius * v.z, center)
		await RenderingServer.frame_post_draw
		var r := TestRig.compare(TestRig.grab(real), TestRig.grab(fake))
		for k in acc:
			acc[k] += r[k] / VIEWS.size()
	if via_parent:
		holder.remove_child(src)
		holder.free()
	else:
		real.world.remove_child(src)
	src.transform = Transform3D.IDENTITY
	parent.add_child(src)
	real.vp.queue_free()
	fake.vp.queue_free()
	return acc
