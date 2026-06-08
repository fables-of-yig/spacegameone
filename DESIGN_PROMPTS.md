# Claude Design Prompts — In-Game Authoring UI

These prompts are for an external visual-design pass (Claude Design / a frontend tool).
You will **upload your own art collection first**, then paste each prompt. The designer
builds the whole design system **from your uploaded art** — it does NOT extend the
game's current placeholder theme (we're throwing that look away).

## How to use this file
1. Upload your art into the design session (see "What to upload" below).
2. Paste **Prompt 1** first — it establishes the design language everything else reuses.
3. Then paste **Prompt 2** and **Prompt 3** in the same session (they inherit Prompt 1's system).
4. Bring back the deliverables and hand them to me. I translate them into Godot
   (`theme.json` + a `.tres` theme + Control layouts; 9-slice PNGs and icons import directly).

## Reality check (so nothing gets wasted)
The output is **web** (HTML/CSS) — Godot 4.6 can't import that as application code.
What I can actually consume:
- **Design tokens** (a JSON block of colors/sizes/spacing) → I turn into the Godot theme.
- **9-slice frame PNGs + icon PNGs** (transparent, with stated slice margins) → import directly.
- **Annotated layout mockups** (the rendered page, as images) → my pixel-faithful build spec.
So every prompt asks for *those three things*, not for a React app.

## What to upload (so the system has what it needs)
- Panel / window / frame art (anything that can become a 9-slice border)
- Button art (ideally normal / hover / pressed states; or one style I can state-shift)
- Icon art (or anything iconographic) — for: save, undo, brush, eraser, entity/spawn,
  projectile, melee, FX/spark, play/test, gear, close, back, next, add, trash
- Fonts (bitmap or TTF)
- Any HUD frames, dividers, sliders, list-row art, swatches, or decorative trim
- Reference sprites / portraits / effect sheets you want the UI to harmonize with

---

## Prompt 1 — Design system & component kit (paste FIRST)

```
I've uploaded a collection of art assets for a retro sci-fi pixel-art game (a 2D
spaceship-combat game + a side-scrolling platformer that share one visual language).
Build a cohesive UI DESIGN SYSTEM derived FROM the art I uploaded — pull the palette,
the type feel, and the panel/button/border treatments out of those assets. Do not
invent a style that ignores them, and do not use a generic default UI look.

TARGET ENGINE: Godot 4.6. The design must be implementable with simple Control nodes:
panels, labels, buttons, sliders, dropdowns, scrollable lists, grids, tabs, progress
bars, text fields, checkboxes/toggles. Anything you style must be expressible as a
static 9-slice texture, a flat color, a bitmap/TTF font, or a simple tween — no
web-only effects (no CSS blur stacks, no DOM animation libraries). Must read clearly
at small sizes (this overlays a pixel-art game).

First, tell me how you read my uploaded art: which pieces are panels/frames, which are
buttons, which are icons, which are fonts, and what palette + mood you extracted.

Then DELIVER:
1. A design-token sheet as a JSON block:
   - colors: panel_bg, panel_alt, panel_dark, border, accent, accent_2, text_title,
     text_body, text_dim, text_button, text_button_hover, text_error, text_success,
     modal_dim_alpha   (all hex; alpha 0–1)
   - fonts: title_size, body_size, hint_size, button_size  (integer px)
   - a spacing scale + notes on corners/borders
2. A component sheet (rendered mockup) showing every state, built from my art:
   - panels (main / alt / dark), section headers, separators
   - buttons (normal / hover / pressed / disabled)
   - text fields, dropdowns, sliders with value labels, checkboxes/toggles
   - scrollable list rows (normal / selected), a 2-col grid cell, tabs, progress bar
   - a modal/dialog frame, a small toast/notification chip
3. EXPORTABLE PNG ART (transparent, 1x and 2x), cut from / styled after my uploads:
   - 9-slice frames for: panel_main, panel_alt, panel_dark, button_normal,
     button_hover, button_pressed — and state the slice margins (px) for each
   - a 24x24 icon set: save, undo, brush, eraser, entity/spawn, projectile, melee,
     FX/spark, play/test, gear, close, back, next, add, trash
If my uploaded art doesn't cover one of these, adapt the closest piece and tell me which.
```

---

## Prompt 2 — Combat Workshop (paste SECOND)

> **Note on engine reality (don't design around features that can't be backed):**
> The runtime has TWO different combat models, so the workshop has two tracks.
> - **Enemy track:** an enemy's "attacks" are NOT free-form hitbox/projectile editors —
>   they're behavior rules (a `shoot`/`attack` block) plus stat fields (melee range,
>   projectile speed/damage, trigger frames). Its hurtbox is derived from the body, not
>   drawn by hand. This track is what's built first.
> - **Player track:** the player DOES have rich authored attacks (per-frame melee
>   hitboxes, combos) and rich projectiles (homing, explosive, trails). This is real and
>   authorable.
> - **FX is engine-fixed.** There is no effects registry to pick from — the only
>   author-controllable "FX" is a projectile's *explosion* settings (blast radius,
>   explosion damage, break-blocks). Do NOT design a general "pick an effect" gallery;
>   it has no data behind it.

```
Reuse the design system, tokens, and 9-slice frames you just built from my uploaded art.

Design a full-screen, guided "Combat Workshop" for the same retro sci-fi pixel game
(Godot 4.6 — implementable as Control nodes; same constraints as the design-system
task). Layout: a left-rail step list + a main work area + a persistent bottom nav
(Back / Next / Test / Save). It has TWO tracks the user picks between on entry:
"Build an Enemy" and "Build the Player's Attacks". Design mockups for BOTH.

=== ENEMY TRACK ===
STEP E1 — Identity & Sprite: id, display name, category (enemy / boss), sprite set
  (a scrollable thumbnail grid of available sprite folders, or "none → placeholder
  box"), movement mode (ground / hover / fly). When hover/fly is chosen, reveal bob
  amplitude + bob speed. A live preview pane plays the chosen sprite.
STEP E2 — Stats & Combat: hp, contact damage, contact cooldown, move speed; a MELEE
  group (range, damage, which animation frame triggers the hit); a RANGED group
  (projectile speed, damage, range, which frame fires). Show the body/hurtbox box on
  the preview (read-only — it comes from the sprite size).
STEP E3 — Behavior: assemble AI as a readable "WHEN [condition] → DO [action]" rule
  list (snapping LEGO, not a tree editor). Conditions: always, player near, player
  seen, wall ahead, ledge ahead, grounded, in air, hp low, cooldown ready. Actions:
  idle, walk, walk left/right, pursue, flee, fly-pursue, fly-flee, jump, dash, turn
  around, patrol point, melee attack, shoot. Each rule shows its few params inline.
STEP E4 — Test Arena & Review: a summary card + big buttons "Spawn & Fight",
  "Tweak" (jump to any step), "Save". This is the core loop — fight it, tweak, re-fight.

=== PLAYER TRACK ===
STEP P1 — Attacks: a list of the player's attacks with "add attack" branching MELEE
  or PROJECTILE:
   - MELEE: active hit frames, hitbox offset x/y, hitbox width/height, damage,
     knockback, cooldown, optional combo→next. Show the hitbox as a draggable/resizable
     box over the sprite preview.
   - PROJECTILE: pick/define the projectile it fires (see P2), plus muzzle offset,
     cooldown, hold behavior (full-auto / single / charge-release).
STEP P2 — Projectiles: define a projectile — speed, damage, gravity, lifetime, pierce
  (toggle), homing (toggle + strength slider), rotate-to-velocity (toggle), explosive
  (toggle → reveals blast radius, explosion damage, break-blocks toggle), sprite sheet
  + frame size/count, trail color, hitbox w/h. Show a trajectory preview.
STEP P3 — Review & Save: summary + Save.

DELIVER: a rendered mockup of every step in BOTH tracks, the track-select entry, the
left-rail + bottom-nav chrome, and notes on spacing/states. Reuse the established
tokens and 9-slice frames — do not introduce a second style.
```

---

## Prompt 3 — Live edit-mode HUD + tile palette + dev console (paste THIRD)

```
Reuse the design system, tokens, and 9-slice frames you built from my uploaded art.

Design the in-world live-editing chrome for the same retro sci-fi pixel game (Godot
4.6, Control nodes). These overlay the running game while I build a level. Three
connected pieces:

1. EDIT-MODE HUD: a compact, non-intrusive toolbar (corner or top strip) showing:
   current mode (Tiles vs Entities), current tool (paint / erase), the selected
   tile/entity, undo availability, save state ("unsaved changes" indicator), and the
   key hints (paint, erase, switch mode, palette, undo, save, exit). Must NOT cover the
   play area. Plus a thin status line for messages ("saved", "room not found").
2. TILE PALETTE: a floating panel showing the current tileset as a selectable atlas
   grid, the chosen tile highlighted, flip-H / flip-V toggles, and a "solid / collision"
   toggle for the cell being painted. Scrollable for big tilesets.
3. DEV CONSOLE: a bottom-anchored slide-up terminal — a colored output log (success /
   warn / error lines) above a single input line, with a "commands" helper chip strip
   for the common verbs (help, flag, spawn, fire, wizard, workshop, add_poi). Should
   read as a polished retro terminal, not a raw text box.

DELIVER: rendered mockups of all three (docked over a mock game scene so I can confirm
they don't obstruct play), plus state variants (console collapsed vs open; HUD in
tile-mode vs entity-mode). Reuse the established tokens and 9-slice frames.
```

---

## What I need back (hand me these)
- The **token JSON** from Prompt 1 (→ becomes the Godot `theme.json` + `.tres`).
- The **9-slice frame PNGs** (with slice margins) and the **icon PNGs** (→ import directly).
- The **layout mockup images** for every screen in Prompts 2 & 3 (→ my build spec).
- A note on **which uploaded asset maps to which role**, so I wire the right files.
