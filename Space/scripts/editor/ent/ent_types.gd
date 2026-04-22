extends RefCounted

# Shared constants for the entity sprite editor. Kept in its own
# RefCounted module so child panels can preload it without touching
# each other's scripts (no circular preloads, no class_name shadow).

const CATEGORIES: Array = [
    "enemy",
    "boss",
    "interactable",
    "pickup",
    "logic",
    "fx",
    "other",
]

static func category_color(cat: String) -> Color:
    if cat == "enemy": return Color(0.95, 0.35, 0.4, 1.0)
    if cat == "boss": return Color(1.0, 0.15, 0.2, 1.0)
    if cat == "interactable": return Color(0.4, 0.7, 1.0, 1.0)
    if cat == "pickup": return Color(1.0, 0.85, 0.25, 1.0)
    if cat == "logic": return Color(0.7, 0.5, 1.0, 1.0)
    if cat == "fx": return Color(0.45, 0.9, 0.85, 1.0)
    return Color(0.7, 0.75, 0.85, 1.0)
