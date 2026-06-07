extends SceneTree

# Headless smoke for the in-game dev console's persistence + validation path.
# Runs in --script mode, so it only touches class_name/preload code (autoloads
# are NOT loaded under --script — that's why this can't exercise the trigger
# ENGINE; the engine + console construction are verified by booting the MV
# scene instead, which does load autoloads).
#
# Verifies:
#   1. EcaSchema type lookups — the console's pre-paste validation primitives
#   2. PedIO save/load roundtrip — the console's persistence path, including
#      that a console-shaped trigger passes PedIO's own validation
#
# Run: godot --headless --path <project> --script res://tools/dev_console_smoke.gd

const PedIO := preload("res://Space/scripts/shared/ped/ped_io.gd")
const EcaSchema := preload("res://Space/scripts/editor/dlg/eca_schema.gd")

const PACK_ID := "dev_console_smoke"
const RULE_ID := "smoke_on_interact"


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	var ok := _run()
	quit(0 if ok else 1)


func _run() -> bool:
	if not MvPackLoader.create_empty_pack(PACK_ID, "Dev Console Smoke"):
		push_error("dev_console_smoke: bootstrap failed")
		return false

	var rule := {
		"id": RULE_ID,
		"event": "interact",
		"conditions": [{"type": "has_tag", "tag": "lever"}],
		"actions": [{"type": "log", "message": "console smoke fired"}],
	}

	# 1) The validation primitives the console relies on resolve in EcaSchema.
	if EcaSchema.find_action_schema("log").is_empty():
		push_error("dev_console_smoke: EcaSchema is missing action 'log'")
		return false
	if EcaSchema.find_condition_schema("has_tag").is_empty():
		push_error("dev_console_smoke: EcaSchema is missing condition 'has_tag'")
		return false
	if not EcaSchema.event_type_names().has("interact"):
		push_error("dev_console_smoke: EcaSchema is missing event 'interact'")
		return false

	# 2) Persistence roundtrip via the console's save path (PedIO), including
	#    PedIO's own validation accepting a console-shaped trigger.
	var root := PedIO.load_triggers(PACK_ID)
	var arr: Array = root.get("triggers", [])
	arr.append(rule)
	root["triggers"] = arr
	if not PedIO.save_triggers(PACK_ID, root):
		push_error("dev_console_smoke: PedIO.save_triggers rejected the rule")
		return false
	if not _has_id(PedIO.load_triggers(PACK_ID).get("triggers", []), RULE_ID):
		push_error("dev_console_smoke: rule did not survive the save/load roundtrip")
		return false

	print("[dev_console_smoke] PASS — EcaSchema validation + PedIO persist roundtrip OK")
	return true


func _has_id(rules: Array, rid: String) -> bool:
	for r in rules:
		if typeof(r) == TYPE_DICTIONARY and str((r as Dictionary).get("id", "")) == rid:
			return true
	return false
