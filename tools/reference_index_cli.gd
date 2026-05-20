extends SceneTree


func _init() -> void:
	_run_and_quit.call_deferred(OS.get_cmdline_user_args())


func _run_and_quit(args: Array) -> void:
	var ok := _run(args)
	quit(0 if ok else 1)


func _run(args: Array) -> bool:
	var command := "scan"
	var pack_id := "demo"
	var kind := ""
	var id := ""
	if not args.is_empty() and not str(args[0]).begins_with("--"):
		command = str(args[0]).strip_edges()
	var i := 1 if not args.is_empty() and command == str(args[0]).strip_edges() else 0
	while i < args.size():
		var arg := str(args[i])
		match arg:
			"--pack":
				i += 1
				if i < args.size():
					pack_id = str(args[i]).strip_edges()
			"--kind":
				i += 1
				if i < args.size():
					kind = str(args[i]).strip_edges()
			"--id":
				i += 1
				if i < args.size():
					id = str(args[i]).strip_edges()
			_:
				push_error("reference_index_cli: unknown arg '%s'" % arg)
				return false
		i += 1

	if pack_id.is_empty():
		push_error("reference_index_cli: empty pack id")
		return false

	var index := ContentReferenceIndex.build(pack_id)
	match command:
		"scan":
			for line_v in ContentReferenceIndex.summary_lines(index):
				print(str(line_v))
			return true
		"refs":
			if kind.is_empty() or id.is_empty():
				push_error("reference_index_cli: refs requires --kind and --id")
				return false
			for line_v in ContentReferenceIndex.summary_lines(index, kind, id):
				print(str(line_v))
			return true
		_:
			push_error("reference_index_cli: unknown command '%s'" % command)
			return false
