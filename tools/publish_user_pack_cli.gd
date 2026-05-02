extends SceneTree


func _init() -> void:
	var args: Array = OS.get_cmdline_user_args()
	if args.is_empty():
		_print_usage()
		quit(2)
		return

	var command := str(args[0]).strip_edges().to_lower()
	match command:
		"publish":
			_handle_publish(args.slice(1))
		_:
			push_error("Unknown publish_user_pack_cli command '%s'" % command)
			_print_usage()
			quit(2)


func _handle_publish(args: Array) -> void:
	if args.is_empty():
		push_error("publish requires a pack id")
		quit(2)
		return

	var pack_id := str(args[0]).strip_edges()
	if pack_id.is_empty():
		push_error("publish requires a non-empty pack id")
		quit(2)
		return

	var user_root := "user://Packs/%s/" % pack_id
	var content_root := "res://Content/%s/" % pack_id
	if not DirAccess.dir_exists_absolute(user_root):
		push_error("No user pack exists at %s" % user_root)
		quit(1)
		return
	if not FileAccess.file_exists(user_root + "Pack.json"):
		push_error("User pack '%s' has no Pack.json" % pack_id)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(content_root)
	var stats := {"copied": 0, "failed": 0}
	_copy_dir_recursive(user_root, content_root, stats)

	print("[publish_user_pack_cli] Published user pack '%s' into res://Content/%s/" % [pack_id, pack_id])
	print("[publish_user_pack_cli] Files copied: %d, failed: %d" % [int(stats["copied"]), int(stats["failed"])])
	quit(1 if int(stats["failed"]) > 0 else 0)


func _copy_dir_recursive(src: String, dst: String, stats: Dictionary) -> void:
	var dir := DirAccess.open(src)
	if dir == null:
		push_error("Cannot open source directory %s" % src)
		stats["failed"] = int(stats["failed"]) + 1
		return

	DirAccess.make_dir_recursive_absolute(dst)
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue

		var src_full := src.rstrip("/") + "/" + name
		var dst_full := dst.rstrip("/") + "/" + name
		if dir.current_is_dir():
			_copy_dir_recursive(src_full, dst_full, stats)
			continue

		var rf := FileAccess.open(src_full, FileAccess.READ)
		if rf == null:
			push_error("Cannot read %s" % src_full)
			stats["failed"] = int(stats["failed"]) + 1
			continue
		var bytes := rf.get_buffer(rf.get_length())
		rf.close()

		var wf := FileAccess.open(dst_full, FileAccess.WRITE)
		if wf == null:
			push_error("Cannot write %s" % dst_full)
			stats["failed"] = int(stats["failed"]) + 1
			continue
		wf.store_buffer(bytes)
		wf.close()
		stats["copied"] = int(stats["copied"]) + 1
	dir.list_dir_end()


func _print_usage() -> void:
	print("publish_user_pack_cli commands:")
	print("  publish <pack_id>")
