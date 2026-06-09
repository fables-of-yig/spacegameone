# Nebula Settings catalog — the single data-driven source of truth for the
# in-game Settings screen (Graphics / Audio / Gameplay / Controls). The screen
# (nebula_settings_screen.gd) renders rows generically from this; SettingsManager
# stores every value and applies the ones marked `wired`.
#
# Honesty contract (per the "no skeleton lies" rule): `wired` is true ONLY when
# the value actually drives engine/runtime state today. Everything else persists
# to user://settings.json but reads as "PREVIEW — not yet wired" in the UI, so no
# control silently no-ops. Flip a setting's `wired` flag (and add its apply in
# SettingsManager._apply_one) the day it gets a real backing.
#
# No class_name — preload this script (matches the DlgIO/EffIO IO convention).
#
# Setting schema:
#   { key, label, kind, section, default, wired,
#     hint?              : String shown dim under the label
#     options?           : Array[{label, value}]  (segmented | select)
#     source?            : "resolution"           (dynamic select options)
#     min?, max?, step?, unit?                     (slider) }
# kind ∈ segmented | select | toggle | slider | keybinds_cta

const TABS: Array = [
	{
		"id": "graphics",
		"label": "Graphics",
		"groups": [
			{
				"label": "Display",
				"settings": [
					{
						"key": "window_mode", "label": "Display mode", "kind": "segmented",
						"section": "video", "default": "fullscreen", "wired": true,
						"options": [
							{"label": "Fullscreen", "value": "exclusive_fullscreen"},
							{"label": "Borderless", "value": "fullscreen"},
							{"label": "Windowed", "value": "windowed"},
						],
					},
					{
						"key": "resolution", "label": "Resolution", "kind": "select",
						"section": "video", "default": "1920x1080", "wired": true,
						"source": "resolution",
						"hint": "Applies in windowed mode.",
					},
					{
						"key": "vsync", "label": "V-Sync", "kind": "toggle",
						"section": "graphics", "default": true, "wired": true,
					},
					{
						"key": "fps_limit", "label": "Frame-rate limit", "kind": "segmented",
						"section": "graphics", "default": "144", "wired": true,
						"options": [
							{"label": "30", "value": "30"},
							{"label": "60", "value": "60"},
							{"label": "120", "value": "120"},
							{"label": "144", "value": "144"},
							{"label": "Unlimited", "value": "0"},
						],
					},
				],
			},
			{
				"label": "Quality",
				"settings": [
					{
						"key": "quality_preset", "label": "Preset", "kind": "segmented",
						"section": "graphics", "default": "high", "wired": false,
						"options": [
							{"label": "Low", "value": "low"}, {"label": "Medium", "value": "medium"},
							{"label": "High", "value": "high"}, {"label": "Ultra", "value": "ultra"},
						],
					},
					{
						"key": "texture_detail", "label": "Texture detail", "kind": "select",
						"section": "graphics", "default": "high", "wired": false,
						"options": [
							{"label": "Low", "value": "low"}, {"label": "Medium", "value": "medium"},
							{"label": "High", "value": "high"}, {"label": "Ultra", "value": "ultra"},
						],
					},
					{
						"key": "shadows", "label": "Shadows", "kind": "select",
						"section": "graphics", "default": "high", "wired": false,
						"options": [
							{"label": "Off", "value": "off"}, {"label": "Low", "value": "low"},
							{"label": "High", "value": "high"},
						],
					},
					{
						"key": "anti_aliasing", "label": "Anti-aliasing", "kind": "select",
						"section": "graphics", "default": "taa", "wired": false,
						"options": [
							{"label": "Off", "value": "off"}, {"label": "FXAA", "value": "fxaa"},
							{"label": "TAA", "value": "taa"}, {"label": "MSAA ×2", "value": "msaa2"},
							{"label": "MSAA ×4", "value": "msaa4"},
						],
					},
					{"key": "bloom", "label": "Bloom", "kind": "toggle", "section": "graphics", "default": true, "wired": false},
					{"key": "motion_blur", "label": "Motion blur", "kind": "toggle", "section": "graphics", "default": false, "wired": false},
				],
			},
			{
				"label": "Calibration",
				"settings": [
					{"key": "brightness", "label": "Brightness", "kind": "slider", "section": "graphics", "default": 50, "wired": false, "min": 0, "max": 100, "step": 1},
					{"key": "ui_scale", "label": "UI scale", "kind": "slider", "section": "graphics", "default": 100, "wired": true, "min": 80, "max": 130, "step": 1, "unit": "%"},
				],
			},
		],
	},
	{
		"id": "audio",
		"label": "Audio",
		"groups": [
			{
				"label": "Levels",
				"settings": [
					{"key": "master", "label": "Master", "kind": "slider", "section": "audio", "default": 80, "wired": true, "min": 0, "max": 100, "step": 1, "unit": "%"},
					{"key": "music", "label": "Music", "kind": "slider", "section": "audio", "default": 65, "wired": true, "min": 0, "max": 100, "step": 1, "unit": "%", "hint": "Bus volume set; routing pending."},
					{"key": "sfx", "label": "Effects", "kind": "slider", "section": "audio", "default": 85, "wired": true, "min": 0, "max": 100, "step": 1, "unit": "%", "hint": "Bus volume set; routing pending."},
					{"key": "voice", "label": "Voice", "kind": "slider", "section": "audio", "default": 80, "wired": true, "min": 0, "max": 100, "step": 1, "unit": "%", "hint": "Bus volume set; routing pending."},
					{"key": "interface", "label": "Interface", "kind": "slider", "section": "audio", "default": 70, "wired": false, "min": 0, "max": 100, "step": 1, "unit": "%"},
					{"key": "ambience", "label": "Ambience", "kind": "slider", "section": "audio", "default": 60, "wired": false, "min": 0, "max": 100, "step": 1, "unit": "%"},
				],
			},
			{
				"label": "Output",
				"settings": [
					{"key": "mute_when_unfocused", "label": "Mute when unfocused", "kind": "toggle", "section": "audio", "default": true, "wired": true},
					{
						"key": "dynamic_range", "label": "Dynamic range", "kind": "segmented",
						"section": "audio", "default": "normal", "wired": false,
						"options": [
							{"label": "Night", "value": "night"}, {"label": "Normal", "value": "normal"},
							{"label": "Cinematic", "value": "cinematic"},
						],
					},
					{"key": "subtitles", "label": "Subtitles", "kind": "toggle", "section": "audio", "default": true, "wired": false},
				],
			},
		],
	},
	{
		"id": "gameplay",
		"label": "Gameplay",
		"groups": [
			{
				"label": "Combat",
				"settings": [
					{"key": "aim_assist", "label": "Aim assist", "kind": "toggle", "section": "gameplay", "default": true, "wired": false},
					{"key": "damage_numbers", "label": "Damage numbers", "kind": "toggle", "section": "gameplay", "default": true, "wired": false},
					{"key": "camera_shake", "label": "Camera shake", "kind": "slider", "section": "gameplay", "default": 40, "wired": false, "min": 0, "max": 100, "step": 1, "unit": "%"},
				],
			},
			{
				"label": "Session",
				"settings": [
					{
						"key": "language", "label": "Language", "kind": "select",
						"section": "gameplay", "default": "english", "wired": false,
						"options": [{"label": "English", "value": "english"}],
					},
					{
						"key": "autosave", "label": "Autosave", "kind": "select",
						"section": "gameplay", "default": "every_10", "wired": false,
						"options": [
							{"label": "Off", "value": "off"}, {"label": "Every 5 min", "value": "every_5"},
							{"label": "Every 10 min", "value": "every_10"}, {"label": "Every 15 min", "value": "every_15"},
							{"label": "On dock only", "value": "on_dock"},
						],
					},
					{"key": "tutorial_hints", "label": "Tutorial hints", "kind": "toggle", "section": "gameplay", "default": true, "wired": false},
				],
			},
			{
				"label": "Interface",
				"settings": [
					{
						"key": "authored_ui_path", "label": "Use authored pack UI", "kind": "toggle",
						"section": "gameplay", "default": false, "wired": true,
						"hint": "Render the loaded pack's authored HUD / pause screens instead of the built-in Nebula overlays. Falls back to Nebula when a pack has no authored screen.",
					},
				],
			},
		],
	},
	{
		"id": "controls",
		"label": "Controls",
		"groups": [
			{
				"label": "Input",
				"settings": [
					{
						"key": "primary_device", "label": "Primary device", "kind": "segmented",
						"section": "controls", "default": "keyboard", "wired": false,
						"options": [{"label": "Keyboard", "value": "keyboard"}, {"label": "Gamepad", "value": "gamepad"}],
					},
					{"key": "mouse_sensitivity", "label": "Mouse sensitivity", "kind": "slider", "section": "controls", "default": 8, "wired": false, "min": 1, "max": 20, "step": 1},
					{"key": "gamepad_sensitivity", "label": "Gamepad sensitivity", "kind": "slider", "section": "controls", "default": 10, "wired": false, "min": 1, "max": 20, "step": 1},
					{"key": "invert_y", "label": "Invert Y", "kind": "toggle", "section": "controls", "default": false, "wired": false},
					{"key": "vibration", "label": "Controller vibration", "kind": "toggle", "section": "controls", "default": true, "wired": false},
				],
			},
			{
				"label": "Key Bindings",
				"settings": [
					{"key": "keybindings", "label": "Edit Keybindings", "kind": "keybinds_cta", "section": "controls", "default": null, "wired": true,
						"hint": "Rebind keyboard, mouse, and controller inputs for every action."},
				],
			},
		],
	},
]


static func tabs() -> Array:
	return TABS.duplicate(true)
