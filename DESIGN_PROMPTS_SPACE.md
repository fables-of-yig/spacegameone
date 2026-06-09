# Claude Design prompts — Space (SSB) authoring screens

These are for the in-game **Space** authoring tools (Frontier 3). They build on
the existing **Nebula sci-fi game-UI design system** (the `nebulous/` bundle) —
the same armored gunmetal windows, glossy cyan capsule controls, Robyn Brutalist
Digital type, painted icons. Drop the Nebula bundle into Claude Design first, then
give it each prompt below. **Output = Godot 4.6 `Control` mockups / specs** (we
recreate via `Theme`/`StyleBoxTexture`, like the existing overlays). Everything
must read clearly overlaid on the dark starfield game.

Two of these screens already exist as functional overlays (galaxy + map editor);
those prompts are for **visual polish / a better layout**. The encounters one is
**net-new UI** we need designed before building.

---

## Prompt 1 — Galaxy Editor (exists; polish)

> Design a full-screen **Galaxy Editor** for a sci-fi space game, in the Nebula
> design system. It's a node-graph of star systems over a deep-space backdrop.
> Elements: a top armored toolbar (title "GALAXY", a Move/Link segmented toggle,
> "+ System", "Save", and a close ✕); the main canvas shows **system nodes**
> (glowing cyan discs sized by the star, the current system marked gold, the
> selected one ringed) connected by **jump lanes** (thin steel lines; a
> gold "linking" line follows the cursor in Link mode); a right **inspector
> panel** for the selected system (name field, star-size slider, a read-only
> list of its links, a POI count, and a "Delete system" button); a bottom-left
> key-hint/status pill. Show hover/selected/dragging states for nodes. Give me
> the node visual (disc + label + selected ring), the lane style, the toolbar,
> and the inspector. It must stay legible with 30+ nodes.

## Prompt 2 — In-System Map Editor (exists; polish)

> Design an in-world **System Map Editor** overlay for a sci-fi space game
> (Nebula design system), shown over the live system view (a star with orbiting
> POIs). A top armored toolbar: title "MAP EDITOR", a row of "+ POI type"
> buttons (Station, Resource, Anomaly, Ruin, Salvage — each with its painted
> type icon/color), "Save", close ✕. POIs are markers on their orbit rings; show
> a **selected POI** state (gold ring + a small handle) and a faint orbit-ring
> guide from the star. A compact right panel for the selected POI: name field,
> type (read-only badge), "Delete POI". Bottom-left key-hint pill (drag move ·
> click select · RMB delete · Save). Give me the POI marker states, the orbit-
> ring guide, the toolbar with type buttons, and the selected panel.

## Prompt 3 — Encounters Editor (NEW — design before build)

> Design an **Encounters Editor** for a sci-fi space game in the Nebula design
> system — a full-screen guided editor for void/random-encounter definitions.
> Chrome like the Combat Workshop: header (title "ENCOUNTERS" + close ✕), a left
> **list rail** of encounters (each row: title + a threat tag chip
> none/low/med/high + enabled dot), a "+ New encounter" button, and a scrolling
> **detail panel** for the selected encounter with these grouped sections:
> - **Identity**: title (text), enabled (toggle), threat (segmented: none/low/
>   med/high), weight (number, "how often"), unique (toggle).
> - **Gating**: day range (min/max number fields), cooldown hours (number),
>   required flags + excluded flags (chip/tag list editors), chain-from
>   (encounter picker).
> - **Spawn**: a list of enemy ships to spawn (ship-id picker + count rows,
>   add/remove).
> - **Story nodes**: a compact **branching node list** (WHEN→THEN style rows or
>   a small node map) for the encounter's choices/outcomes — reuse the same row
>   idiom as the trigger/dialogue editors (a labeled clause with add/remove).
> Bottom bar: ← Back · ▶ Test · Save. Give me: the list-rail row (with threat
> chip + enabled dot), the section headers, the chip/tag list editor, the
> spawn-row, and the story-node row. Keep it legible at small sizes over the
> dark UI.

---

## Notes for whoever wires these (me)

- Galaxy + Map editors are live: `Space/scripts/runtime/space_galaxy_editor.gd`
  (`galaxyedit`) and `space_map_editor.gd` (`mapedit`). They use `NebulaUi`/
  `NebulaTheme` + `_draw`; the prompts above are to upgrade their look, not their
  data flow (systems.json via `SystemIO`).
- Encounters: data is `GameTuning/encounters.json` — a top-level tuning block
  (`enabled`, `min_void_time`, `encounter_chance_per_sec`, intervals,
  `max_encounters_per_trip`, `void_distance`) plus the encounter **def table**
  (int-keyed: `{title, weight, unique, threat, cooldown_hours, min_day, max_day,
  required_flags[], excluded_flags[], chain_prev, sets_flags[], spawn[], nodes{}}`).
  `EncounterManager.load_encounters` consumes the table; `_load_encounter_tuning`
  the config. **Before building the editor, fully map the def-table vs tuning
  split in the actual file and the `spawn`/`nodes` shapes** — then build against
  this design. `nodes` is an event/branch tree (overlaps the dialogue model).
