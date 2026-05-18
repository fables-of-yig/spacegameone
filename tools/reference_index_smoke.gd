extends SceneTree

const ContentReferenceIndex := preload("res://Space/scripts/editor/content_reference_index.gd")
const PlanetLandingBossRecipe := preload("res://Space/scripts/editor/recipes/planet_landing_boss_recipe.gd")

const PACK_ID := "reference_index_smoke"


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	var ok := _run()
	quit(0 if ok else 1)


func _run() -> bool:
	if not MvPackLoader.create_empty_pack(PACK_ID, "Reference Index Smoke"):
		push_error("reference_index_smoke: bootstrap failed")
		return false
	var result := PlanetLandingBossRecipe.apply(PACK_ID, {
		"system_id": "start",
		"planet_name": "Reference Landing",
		"key_item_id": "key_silver",
		"boss_entity_id": "golden_boss",
	})
	if not bool(result.get("ok", false)):
		for error_v in result.get("errors", []):
			push_error("[reference_index_smoke] %s" % str(error_v))
		return false

	var index := ContentReferenceIndex.build(PACK_ID)
	if not _has_definition(index, "item", "boss_core"):
		push_error("reference_index_smoke: missing boss_core item definition")
		return false
	if not _has_definition(index, "entity", "golden_boss"):
		push_error("reference_index_smoke: missing golden_boss entity definition")
		return false
	if not _has_reference(index, "item", "boss_core", "Entity 'golden_boss'"):
		push_error("reference_index_smoke: missing boss_core entity drop reference")
		return false
	if not _has_reference(index, "item", "boss_core", "boss_defeated_reward"):
		push_error("reference_index_smoke: missing boss_core trigger reward reference")
		return false
	if not _has_reference(index, "entity", "golden_boss", "boss_intro"):
		push_error("reference_index_smoke: missing golden_boss trigger spawn reference")
		return false
	if not _has_reference(index, "room", "region_default/landing", "Pack.json"):
		push_error("reference_index_smoke: missing manifest entry room reference")
		return false

	print("[reference_index_smoke] PASS definitions=%d references=%d" % [
		_as_array(index.get("definitions", [])).size(),
		_as_array(index.get("references", [])).size(),
	])
	return true


func _has_definition(index: Dictionary, kind: String, id: String) -> bool:
	for def_v in _as_array(index.get("definitions", [])):
		if typeof(def_v) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = def_v
		if str(definition.get("kind", "")) == kind and str(definition.get("id", "")) == id:
			return true
	return false


func _has_reference(index: Dictionary, kind: String, id: String, source_fragment: String) -> bool:
	for ref_v in ContentReferenceIndex.find_references_in_index(index, kind, id):
		if typeof(ref_v) != TYPE_DICTIONARY:
			continue
		var ref: Dictionary = ref_v
		if str(ref.get("source", "")).contains(source_fragment):
			return true
	return false


func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
