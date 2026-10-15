class_name OctaBakeJob
extends RefCounted

signal progress(done: int, total: int, text: String)
signal resume
signal completed(success: bool)

var cancelled := false
var started_msec := Time.get_ticks_msec()
var paced := false
var max_views := 0
var last_batch := 0
var wait_render := false
var wait_frame := -1
var running := true
var atlas: OctaAtlas
var card: Node3D


func cancel() -> void:
	cancelled = true


func seconds_left(done: int, total: int) -> float:
	if done <= 0:
		return -1.0
	return (Time.get_ticks_msec() - started_msec) / 1000.0 * float(total - done) / float(done)
