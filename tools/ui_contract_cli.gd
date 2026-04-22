extends SceneTree

const ContentValidator := preload("res://Space/scripts/editor/content_validator.gd")
const UiContract := preload("res://Space/scripts/ui/ui_contract.gd")

const SUPPORTED_FEATURES_PATH := "res://SUPPORTED_FEATURES.md"
const DEFAULT_SMOKE_PACK := "demo"


func _init() -> void:
	var args: Array = OS.get_cmdline_user_args()
	if args.is_empty():
		_print_usage()
		quit(2)
		return

	var command := str(args[0]).strip_edges().to_lower()
	match command:
		"sync-docs":
			_handle_sync_docs(args.slice(1))
		"validate-pack":
			_handle_validate_pack(args.slice(1))
		"validate-smoke-pack":
			_handle_validate_pack([DEFAULT_SMOKE_PACK])
		_:
			push_error("Unknown ui_contract_cli command '%s'" % command)
			_print_usage()
			quit(2)


func _handle_sync_docs(args: Array) -> void:
	var check_only := false
	for arg_v in args:
		if str(arg_v) == "--check":
			check_only = true
	var rendered := UiContract.render_supported_features_markdown()
	var current := _read_text(SUPPORTED_FEATURES_PATH)
	if check_only:
		if current == rendered:
			print("[ui_contract_cli] SUPPORTED_FEATURES.md is up to date.")
			quit(0)
		else:
			push_error("SUPPORTED_FEATURES.md is out of date. Run sync-docs.")
			quit(1)
		return
	var write_ok := _write_text(SUPPORTED_FEATURES_PATH, rendered)
	if not write_ok:
		quit(1)
		return
	print("[ui_contract_cli] Synced SUPPORTED_FEATURES.md from UiContract.")
	quit(0)


func _handle_validate_pack(args: Array) -> void:
	var pack_id := DEFAULT_SMOKE_PACK
	if not args.is_empty():
		pack_id = str(args[0]).strip_edges()
	if pack_id.is_empty():
		push_error("validate-pack requires a pack id")
		quit(2)
		return
	var issues: Array = ContentValidator.validate(pack_id)
	var errors: int = 0
	var warnings: int = 0
	for issue_v in issues:
		if typeof(issue_v) != TYPE_OBJECT or issue_v == null:
			continue
		var text: String = str(issue_v.text() if issue_v.has_method("text") else issue_v)
		print(text)
		var severity := str(issue_v.severity)
		if severity == "error":
			errors += 1
		elif severity == "warning":
			warnings += 1
	print("[ui_contract_cli] Pack '%s': %d errors, %d warnings" % [pack_id, errors, warnings])
	quit(1 if errors > 0 else 0)


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text


func _write_text(path: String, text: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Could not open %s for write" % path)
		return false
	f.store_string(text)
	f.close()
	return true


func _print_usage() -> void:
	print("ui_contract_cli commands:")
	print("  sync-docs [--check]")
	print("  validate-pack <pack_id>")
	print("  validate-smoke-pack")
