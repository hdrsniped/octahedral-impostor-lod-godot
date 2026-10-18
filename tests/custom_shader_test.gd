extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var hooked: Node3D = DemoObjects.custom_hooked()
	var plain: Node3D = DemoObjects.custom()
	var a1: OctaAtlas = await OctaBaker.bake([hooked], root, null)
	var a2: OctaAtlas = await OctaBaker.bake([plain], root, null)
	var hook_ok: bool = a1 != null and a1.orm != null and a1.emission != null
	var plain_ok: bool = a2 != null and a2.orm == null and a2.emission == null
	print("CUSTOM hook maps orm=%s em=%s" % [a1 != null and a1.orm != null, a1 != null and a1.emission != null])
	print("CUSTOM no hook maps orm=%s em=%s" % [a2 != null and a2.orm != null, a2 != null and a2.emission != null])
	print("RESULT %s (%d failures)" % ["PASS" if hook_ok and plain_ok else "FAIL", 0 if hook_ok and plain_ok else 1])
	quit(0 if hook_ok and plain_ok else 1)
