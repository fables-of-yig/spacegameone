# Shipping a pack as a standalone build

This project is structured so the editor suite can be stripped entirely
from shipped builds. The runtime code that the player actually executes
lives under `Space/scripts/shared/` (IO modules, pack loaders, faction /
quest / system data access). The authoring panels live under
`Space/scripts/editor/` and are not referenced by any runtime code.

## What you need

1. **A working content pack** under `Content/<your_pack_id>/` — assets
   loaded, dialogues authored, factions defined, etc.
2. **A `res://shipped_pack.json`** at the project root pointing the boot
   flow at that pack.
3. **A Godot export preset** that excludes the editor folder from the
   `.pck` and includes only your one pack's content.

## Step 1: drop a `shipped_pack.json` at `res://`

The file is detected by `UICoordinator.is_shipped_build()` at boot;
its presence flips the project from authoring mode to shipped mode
(skips editor panel instantiation, hides editor entry points).

```json
{
  "pack_id": "your_pack_id_here",
  "hide_editor": true
}
```

If this file is missing the project behaves like a normal dev build —
full editor suite, full pack picker. (Don't commit `shipped_pack.json`
to version control; treat it the same way you would an export preset.)

Once present, the boot flow will:

- Detect shipped mode in `Space/scripts/ui/ui_coordinator.gd::is_shipped_build()`
- Skip `setup_editors` entirely — every editor handle on main stays null
- Read `shipped_pack.json` for the `pack_id`, then defer-call
  `main_menu._start_play_pack_menu(pack_id)` from
  `main.gd::_auto_route_to_shipped_pack_if_any()` so the player lands on
  the pack's authored `main_menu` screen instead of the dev launcher.

Missing or malformed `pack_id` in `shipped_pack.json` falls back to dev
behavior with a `push_warning` so the boot stays functional.

## Step 2: configure the export preset

`export_presets.cfg` is gitignored — every author / build machine
configures their own. In Godot's **Project → Export → Add…** dialog:

### Resources tab

- **Filter mode**: `Resources (and dependencies) selected below`
- **Resources to exclude (using filter)**:
  ```
  Space/scripts/editor/*
  ```
  That single filter removes all editor panels + IO not under
  `Space/scripts/shared/`. The runtime code under `runtime/`, `ui/`,
  `autoload/`, `shared/`, and `MV/scripts/` is untouched.
- **Resources to exclude from export non-resource files/folders**:
  ```
  .agents, .claude, docs, tools
  ```
  (Optional — these never get pulled in at runtime anyway, but
  shrinking the export is harmless.)
- **Content packs**: also add a filter for any pack you're *not*
  shipping. Example for a build of `history_hails_no_heroes`:
  ```
  Content/demo/*, Content/golden_path/*, Content/trigger_recipe_smoke/*, Content/world_recipe_smoke/*, Content/reference_index_smoke/*, Content/reference_refactor_smoke/*, Content/quest_schema_smoke/*
  ```
- **Include**: keep `Content/your_pack_id/*` and
  `Space/scripts/shared/*` (they're picked up automatically since
  runtime preloads reference them).

### Options tab

- **Binary format**: leave as default
- **Export with debug**: off for release builds
- Encryption: optional, see below.

## Step 3 (optional): encrypt the `.pck`

Out of scope per current direction — the user explicitly wants players
to be able to look inside the pack folder. If that changes:
**Project → Export → \[preset\] → Encryption** lets you set an AES key
that the engine bakes into the binary. Stops casual unpacking; doesn't
stop determined reverse-engineering.

## What players see

- Boot → no engine main menu, no editor button anywhere → pack's
  authored `main_menu` screen.
- The `Content/<your_pack_id>/` folder remains visible on disk; players
  can look at the JSON, swap assets, etc. (per current decision).
- Cannot reach any editor: the scripts aren't in the export, the
  entry-point tiles in `content_editor.gd` are never instantiated, and
  the dynamic `_mk_editor` calls in `ui_coordinator.gd` return null
  cleanly when their target script is missing.

## Verifying a shipped build locally

Before exporting:

```powershell
# Drop the shipped_pack.json in res://, then:
godot --headless --import
godot
```

If the project boots straight past the dev main menu, that's shipped
mode behaving correctly. If you see the editor tiles, the
`shipped_pack.json` isn't being picked up (check that the path is exactly
`res://shipped_pack.json` and that `FileAccess.file_exists` resolves it).

To go back to dev mode: delete `shipped_pack.json`.

## What lives where (cheat sheet)

| Path | Ships? | Reason |
|---|---|---|
| `Space/scripts/main.gd` | yes | Runtime entry |
| `Space/scripts/autoload/` | yes | Game state |
| `Space/scripts/ui/` (except editor-hosting code paths) | yes | HUD, menus, etc. |
| `Space/scripts/runtime/` | yes | Spawn, world, AI runtime |
| `Space/scripts/shared/` | yes | IO + data modules used by runtime AND editor |
| `Space/scripts/editor/` | **no** | Editor panels (excluded by filter) |
| `MV/scripts/` | yes | MV runtime |
| `Content/<active_pack>/` | yes | The pack you're shipping |
| `Content/<other_pack>/` | **no** | Excluded by filter |
