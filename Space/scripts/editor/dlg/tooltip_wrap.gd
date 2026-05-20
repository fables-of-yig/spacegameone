class_name EditorTooltipWrap
extends RefCounted

# Helper for Godot's built-in Control.tooltip_text path. The default
# tooltip is a single-line Label with autowrap_mode = OFF, so setting
# `tooltip_text = "long help string..."` makes the tooltip stretch the
# full width of the screen and frequently spill past the right edge.
# Godot's tooltip Label DOES respect explicit `\n` hard breaks, so we
# pre-wrap long strings at word boundaries and bake the line breaks into
# the tooltip text itself.
#
# Used in two modes:
#   1. EditorTooltipWrap.wrap_text("long ...") — manual one-off at an
#      assignment site. (Named wrap_text, not wrap, because Godot's
#      PackedStringArray.wrap exists and shadows a global `wrap` call.)
#   2. EditorTooltipWrap.wrap_tree(panel_root) — recursive sweep called
#      once after a panel finishes building its UI. Walks every Control
#      under root and wraps any non-empty tooltip_text in place.
#
# Re-wrapping already-wrapped text is a no-op since each line is already
# under the char budget.
#
# Note: this is approximate char-width wrapping, not pixel-perfect; the
# tooltip Label still does its own measuring. 64 chars at the default
# theme font (~6 px per char) lands around 380-400 px, matching the
# EditorTooltip autoload's _MAX_WIDTH_PX = 380.0.

const DEFAULT_MAX_CHARS: int = 64


static func wrap_text(text: String, max_chars: int = DEFAULT_MAX_CHARS) -> String:
    if text == null or text.is_empty() or max_chars <= 0:
        return text
    var hard_lines := text.split("\n")
    var out := PackedStringArray()
    for hard_v in hard_lines:
        var hard: String = hard_v
        var words := hard.split(" ")
        var current: String = ""
        for w_v in words:
            var w: String = w_v
            var candidate: String = w if current.is_empty() else current + " " + w
            if candidate.length() > max_chars and not current.is_empty():
                out.append(current)
                current = w
            else:
                current = candidate
        if not current.is_empty():
            out.append(current)
    return "\n".join(out)


static func wrap_tree(root: Node, max_chars: int = DEFAULT_MAX_CHARS) -> void:
    if root == null:
        return
    if root is Control:
        var c: Control = root
        if not c.tooltip_text.is_empty():
            c.tooltip_text = wrap_text(c.tooltip_text, max_chars)
    for child in root.get_children():
        wrap_tree(child, max_chars)
