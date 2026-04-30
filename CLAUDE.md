# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SpaceboatMania (MV+ Editor) is a Godot 4.6 GDScript game-authoring tool with two integrated game engines and a full in-editor content pipeline. All gameplay content is JSON-driven and authored through an integrated editor suite.

## Running

Open the project in Godot 4.6: `godot project.godot`

Entry scene: `res://Space/scenes/main.tscn`

Asset ingestion:
```bash
godot --headless --script "res://tools/import_pack.gd" -- --source <path> --pack <id>
godot --headless --import   # refresh import cache after
```

There is no test runner or CI pipeline. Validation is embedded in the editor (`content_validator.gd`). The smoke-test workflow is documented in `TESTING_GUIDE.md`.

## Agent Workflow

Project-local agent prompts live in `.claude/agents/`. The human-readable operating guide and task templates live in `.agents/`.

Use the coordinator/explorer/worker/reviewer flow for non-trivial changes: map the path first, assign bounded ownership, implement the narrow slice, validate contract behavior, run the smallest useful smoke check, then sync docs.

## Two-Engine Architecture

The project runs two separate game engines that share state through `PlanetaryInterface`:

- **Space (SSB)** — 2D spaceship combat, hex grid navigation, fleet management, procedural ships. Scripts in `Space/scripts/`, scene root `Space/scenes/main.tscn`.
- **MV (MVMania)** — Side-scroller platformer with room-based levels, tile collision, entities with behavior trees, dialogue, shops, triggers. Scripts in `MV/scripts/`, scene root `MV/scenes/main.tscn`.

Players land on planets (SSB -> MV) and launch back to space (MV -> SSB). `PlanetaryInterface` is the authoritative state holder for this handoff — it manages pack staging, flag bridging, and state snapshots.

### Flag Bridge

Two namespaces in `PlanetaryInterface`:
- **Planet flags** — per-visit, snapshotted on launch, restored on re-landing. Used by triggers (`set_var`/`var_eq`).
- **Global flags** — never wiped, cross-system. Used for story/faction/credits.

Both fire `flag_changed(scope, name, old, new)`.

## Autoloads

Space-side: `GameManager`, `DataManager`, `AudioManager`, `HexUtil`, `EncounterManager`, `Updater`, `PlanetaryInterface`

MV-side: `PlayerInventory`, `MvGame`, `MvTriggerEngine`, `MvRoomState`, `MvDialogueRunner`, `MvHud`, `MvInventoryScreen`, `MvMapScreen`, `MvSaveManager`, `MvGameOver`, `MvShopUI`

Editor: `EditorTooltip`

Addon: `BeehaveGlobalMetrics`, `BeehaveGlobalDebugger` (behavior tree addon in `addons/beehave/`)

## Content Pack System

Content packs live under `Content/<pack-id>/` (shipped baseline, read-only) and `user://Packs/<pack-id>/` (user edits, writeable). The loader (`MV/scripts/pack_loader.gd`) tries user path first, falls back to shipped, then to `Content/demo/`.

A pack contains JSON data files for rooms, entities, dialogue, triggers, shops, items, abilities, player stats/attacks/projectiles, plus PNGs for tilesets and sprites. See `IMPORTS.md` for the full directory layout.

## Editor Suite

The content editor (`Space/scripts/editor/content_editor.gd`) has 7 tabs: Campaign, Objects, World, Triggers, UI + FX, Audio, Playtest.

Each domain editor (entity, behavior, dialogue, trigger, environment, etc.) has a matching subdirectory under `Space/scripts/editor/` with `*_io.gd` (serialization), `*_list_panel.gd`, `*_detail_panel.gd`, and `*_topbar.gd`.

Playtest roundtrip: the environment editor stages pack/region/room in `PlanetaryInterface`, launches MV, and Ctrl+9 returns to the Space editor.

## God-File Split (Completed Refactoring)

`Space/scripts/runtime/` contains controllers extracted from a former monolithic `main.gd`: `StarfieldRenderer`, `UICoordinator`, `SpawnManager`, `CreativeModeController`, `WorldRenderer`. Also extracted to autoloads: `StationGenerator`, `InputSetup`, `ModuleSprites`.

## Key Conventions

- Treat silent fallback and null-bound UI as bugs (see `ROADMAP.md` Phase 0).
- Validation failures are blockers, not warnings to ignore. The content validator rejects bad data at save time.
- The editor/runtime contract is tracked in `SUPPORTED_FEATURES.md` — if the editor exposes something not listed there, it's a bug.
- Entity AI uses the Beehave addon with leaf actions/conditions in `MV/scripts/entities/leaves/`.
- Authored screens use a universal `AuthoredScreenRuntime` that mounts into hardcoded runtime hosts (HUD, pause, inventory, etc.).

## Key Documentation

- `SUPPORTED_FEATURES.md` — authoritative editor/runtime contract
- `ROADMAP.md` — development phases and acceptance criteria
- `TESTING_GUIDE.md` — canonical pack creation workflow and smoke checklist
- `IMPORTS.md` — asset ingestion pipeline and sprite conventions
