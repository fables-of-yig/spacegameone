extends RefCounted

# Shared input-parsing helpers for the player editor tabs.
# All tabs parse LineEdit text into ints/floats with the same "blank or
# lone sign means fallback" rule — this file is the one source of truth.
#
# Float formatting helpers stay local to each tab: ped_abilities_tab
# uses "%.1f" for near-integer floats to distinguish float params from
# int params in the UI, while equipment/stats prefer clean ints. Those
# stylistic choices don't belong in a shared util.


static func to_int(text: String, fallback: int) -> int:
    var t := text.strip_edges()
    if t.is_empty():
        return fallback
    if t == "-" or t == "+":
        return fallback
    return t.to_int()


static func to_float(text: String, fallback: float) -> float:
    var t := text.strip_edges()
    if t.is_empty():
        return fallback
    if t == "-" or t == "+" or t == ".":
        return fallback
    return t.to_float()
