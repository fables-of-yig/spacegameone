# NPC & Enemy Import Plan

Source: `D:\SPaceAssetsNoisey\4-17\characters\Non-Player Characters\`

This plan covers importing every character and enemy from the asset folder into the content pack system: sprite set creation, animation pose mapping, entity registry entries, and Beehave behavior trees.

---

## Table of Contents

1. [Asset Inventory](#1-asset-inventory)
2. [Sprite Pipeline Per Character](#2-sprite-pipeline-per-character)
3. [Entity Registry Entries](#3-entity-registry-entries)
4. [Behavior Tree Designs](#4-behavior-tree-designs)
5. [Detailed Per-Character Plan](#5-detailed-per-character-plan)
6. [Execution Order](#6-execution-order)

---

## 1. Asset Inventory

### 1A. Standalone Character Packs (individual sprite strip sheets)

| # | Source Folder | Character Type | Available Animations | Sheet Format |
|---|---|---|---|---|
| 1 | `annette-sprites-v1` | NPC/Ally | idle (armed+unarmed), running, crouching, crouch-pose, magic, sword-pose | Horizontal strips (`_stripN.png`) |
| 2 | `bluemagestaff-v3` | NPC/Enemy Mage | idle, walk, walk2, attack(x3), crouch, crouch-attack(x3), jump, double-jump, in-air, fall, death, hithurt, hithurt-crouch, flying, roll, morph-sphere, special | Horizontal strips (`_stripN.png`) |
| 3 | `doublesword-v7` | Enemy Warrior | idle, running(x3 variants), walk, attack1, attack2, attack3, slide-attack, jump, jump-attack, crouch, crouch-hithurt, hithurt, die, slide, wall-slide, stairs-up, stairs-down, landing | Horizontal strips (`_stripN.png`) |
| 4 | `long-sword-free-walk-attack1` | Enemy Warrior (lite) | walk, attack | Horizontal strips |
| 5 | `long-sword-sprites-v5` | Enemy Warrior | idle, running(x2), walk, attack(x3), roll, fall, falling, dying, jump-up, jump-down, crouch, hithurt, crouch-hithurt, stairs-up, death-lying, back | Horizontal strips |
| 6 | `legacy-vania-npc-v7` | NPCs (Castlevania-style) | Multiple characters with idle/walk/etc | Strips + sheets |
| 7 | `Pixel Prototype Enemy` | Prototype placeholder | Basic enemy placeholder | Single folder |

### 1B. Characters > NPC and ENEMIES (per-animation-folder structure)

#### Bosses

| # | Source Folder | Boss Name | Animations | Frame Format |
|---|---|---|---|---|
| 8 | `Boss-Demon` | Demon Boss | idle, attack (with breath), attack (no breath) | Individual frames + spritesheets |
| 9 | `Boss-Dragon-files` | Dragon Boss | idle, fly, fly-attack, fire-breath, death | Individual frames + spritesheets |
| 10 | `Boss-Wendigo-files` | Wendigo Boss | idle, attack, run | Individual frames + sheets per animation |

#### Bridge Enemies

| # | Source Folder | Enemy Name | Animations |
|---|---|---|---|
| 11 | `Bat` | Bat | flying (4f), hang (3f) |
| 12 | `Skeleton` | Bridge Skeleton | walk (6f) |
| 13 | `Sorcerer` | Sorcerer | idle/cast (4f) |
| 14 | `FireballAttack` | Fireball (projectile) | fireball (4f) |
| 15 | `Enemy Death` | Death FX (shared) | death (5f) |

#### Cemetery Enemies

| # | Source Folder | Enemy Name | Animations |
|---|---|---|---|
| 16 | `ghost` | Ghost | float (4f), float-halo variant (4f) |
| 17 | `hell-gato` | Hell Cat | walk/idle (4f) |
| 18 | `skeleton` | Cemetery Skeleton | walk (8f), walk-clothed (8f), rise (6f), rise-clothed (6f) |
| 19 | `EnemyDeath` | Death FX (shared) | death (5f) |

#### Church Enemies

| # | Source Folder | Enemy Name | Animations |
|---|---|---|---|
| 20 | `angel` | Angel | idle, attack |
| 21 | `burning-ghoul` | Burning Ghoul | walk/idle (v1 + v2 variants) |
| 22 | `wizard` | Wizard | idle, fire-attack |
| 23 | `fx/fireball` | Fireball (projectile) | fireball animation |
| 24 | `fx/enemy-death` | Death FX (shared) | death animation |

#### Standalone Enemies (NPC and ENEMIES root)

| # | Source Folder | Enemy Name | Animations |
|---|---|---|---|
| 25 | `crow` | Crow | idle, fly, front-view |
| 26 | `Death Lamp` | Death Lamp | walk, walk-no-lamp, rise |
| 27 | `demon` | Small Demon | idle/walk sprites |
| 28 | `Fire-Skull-Files` | Fire Skull | fire-skull, no-fire variant |
| 29 | `Flying-Eye-Demon` | Flying Eye Demon | fly/idle |
| 30 | `Fox` | Fox (sword variant) | fox, fox-sword |
| 31 | `Ghost` | Flying Ghost | flying animation |
| 32 | `Ghost-Files` | Ghost (detailed) | appear, idle, chase, shriek, vanish |
| 33 | `Hell-Beast-Files` | Hell Beast | idle, breath-attack, fireball, burn |
| 34 | `Hell-Hound-Files` | Hell Hound | idle, walk, run, jump |
| 35 | `meerman` | Meerman | walk/idle |
| 36 | `mummy-idle` | Mummy (idle) | idle only |
| 37 | `mummy-walk` | Mummy (walk) | walk only |
| 38 | `mutant-toad` | Mutant Toad | idle, attack, jump |
| 39 | `Nightmare-Files` | Nightmare Horse | idle, gallop |
| 40 | `Ogre` | Ogre (armed + unarmed) | idle, walk, attack, idle-unarmed, walk-unarmed |
| 41 | `Shotgun Skeleton` | Shotgun Skeleton | idle, shoot |
| 42 | `Shuriken Dude Enemy` | Shuriken Dude | throw (with/without shuriken), shuriken projectile |
| 43 | `slime-idle` | Slime (idle) | idle bounce |
| 44 | `slime-jump` | Slime (jump) | jump |
| 45 | `Spider` | Spider | idle, walk, attack, death, venom, venom-down, venom-up, venom-splat |
| 46 | `Swamp Spider` | Swamp Spider | walk |
| 47 | `Swamp Thing` | Swamp Thing | walk |
| 48 | `Vulture` | Vulture | fly/idle |
| 49 | `Walking Skeleton` | Walking Skeleton | walk |
| 50 | `WereWolf` | Werewolf | idle, run, jump, fall |
| 51 | `Wolf` | Wolf | walk/run |

#### Enemy Packs (numbered theme sets)

| # | Source Folder | Pack Contents | Enemies Per Pack |
|---|---|---|---|
| 52 | `Enemies Pack 1` | dragon, hand, ogre (idle+throw), slime | 4 |
| 53 | `Enemies Pack 2` | amphibean, imp (jump+run), mummy (walk+attack), wolf (idle+run) | 4 |
| 54 | `Enemies pack 3` | flame, ghost, merman (3 color variants x 4 anims), warlock | 4 (+variants) |
| 55 | `Enemies Pack 4` | gargoyle, ghost-wolf (energized + not, multiple anims), skull (flames + skull-only) | 3 |
| 56 | `Enemies Pack 5` | firebat, mage, mage-b, mage-cast, skull, zombie, zombie-attack | 5 |

#### Ninja Enemies

| # | Source Folder | Enemy Name | Animations |
|---|---|---|---|
| 57 | `Ninja Scroller Enemies` | Ninja 1-4 | idle, slash, jump, drop, charge |

#### NPCs (non-combat)

| # | Source Folder | NPC Name | Animations |
|---|---|---|---|
| 58 | `npc man` | NPC Man | idle, idle-b, walk |
| 59 | `npc old-woman` | Old Woman | idle, idle-no-basket, walk, walk-no-basket |
| 60 | `Town NPCs` | Town NPCs (4) | bearded-idle/walk, hat-man-idle/walk, oldman-idle/walk, woman-idle/walk |
| 61 | `Young Woman` | Young Woman | idle, run, walk, skip, hips-dance, slide-dance, snap |

#### Playable Characters (usable as enemies or allies)

| # | Source Folder | Character Name | Animations |
|---|---|---|---|
| 62 | `Bridge Heroine` | Heroine | Base: idle, run, jump, crouch, hurt, attack, crouch-attack, jump-attack, dizzy. Add-ons 1-4: back-flip, climb, dash, special, aura, block, magic, kick, death, drink, slide, charged-attack, crawl, etc. |
| 63 | `Cemetery Hero` | Cemetery Hero | Base: idle, run, jump, crouch, hurt, attack, death. Add-ons: air-attack, charge-attack, crouch-attack, drink, special |
| 64 | `Gun Slinger Girl` | Gun Slinger Girl | idle, run, jump, duck, hurt, shoot, shoot-up, shoot-upwards-special + muzzle-flash, shot, shot-impact FX |
| 65 | `Hooded Hero` | Hooded Hero | idle, run, fall, jump, hurt, crouch, attack, crouch-attack, jump-attack, air-down-attack, climb, roll |
| 66 | `Monk` | Monk | Base: idle, walk, crouch, punch, kick, crouch-kick, flying-kick, fall, hurt, jump. Add-ons: climb, fly-kick, meditation, roll, run, chi-cast, combo, defeated, uppercut |
| 67 | `Ninja Girl` | Ninja Girl | Base: idle, run, fall, jump, crouch, attack, crouch-attack, jump-attack, hurt, death. Add-ons: drink, fall-attack, kick, piercing, up-attack, backflip, charged-attack, climb, pummel, walk |
| 68 | `Ninja-scroller-player` | Ninja (scroller) | death, jump, roll, run, slash |
| 69 | `Rifle man` | Rifle Man | idle, run, jump, fall, hurt, crouch, crouch-shoot, shoot, stand |
| 70 | `Terrible Knight` | Terrible Knight | idle, run, jump, crouch, hurt, attack-side, attack-up, attack-crouch, crouch-sword-attack, jump-attack, jump-sword-attack, climb |

### 1C. enemy_sprites Collection (72 themed packs)

These are numbered enemy packs, each typically containing 3-6 enemies as horizontal sprite strips. Key packs:

| Pack Category | Packs | Typical Enemies |
|---|---|---|
| Fantasy/Dungeon | basement-enemies, cave-monsters, hell-monsters, fire-monsters, mountain-monsters, ruin-enemies | Goblins, skeletons, zombies, bats, mushrooms, elementals, hellhounds, beholders |
| Bosses | basement-bosses, cave-bosses, hell-bosses, field-bosses, desert-bosses, mine-bosses, pirate-bay-bosses, etc. | Large bosses (3 per pack typically) |
| Sci-fi/Modern | cyberpunk-desert-bandits, cyberpunk-beach, lab-enemies, lab-bosses, battle-mecha, robots, space-pirates | Bandits, mechs, robots, mutants |
| Urban | bar-street-enemies, business-enemies, residential-area-enemies, police, prison, homeless | Street fighters, thugs, officers |
| Nature/Water | water-monsters, snow-enemies, pirate-sprites, peasants | Aquatic creatures, snow beasts, pirates |
| NPCs/Civilians | civilian-characters, beach-crowd, blacksmith, peasants | Non-combat characters |
| Vehicles/Items | bike-constructor, car-constructor, gun-constructor | Vehicle/weapon parts (modular) |

---

## 2. Sprite Pipeline Per Character

For each character, the import process is:

### Step 2A: Determine Sheet Format

Source assets come in three formats. Each needs different handling:

1. **Horizontal strip (`*_stripN.png`)** — Already MV-compatible. N = frame count, all frames in one row. This is the ideal format.
2. **Individual frames (`frame1.png`, `frame2.png`, ...)** — Must be stitched into horizontal strip using ImageMagick: `convert +append frame1.png frame2.png ... strip.png`
3. **Grid spritesheet** — Must be sliced into per-animation strips or converted to single-row strips.

### Step 2B: Create Sprite Set Directory

Target: `Content/demo/Sprites/<entity_id>/`

Each animation becomes one horizontal strip PNG file:
```
Content/demo/Sprites/bat_bridge/
  idle.png          (from bat-hang strip, 3 frames)
  walk.png          (from bat-flying strip, 4 frames)
```

Naming convention: animation PNGs are named by pose (`idle.png`, `walk.png`, `attack.png`, `hurt.png`, `death.png`, etc.).

### Step 2C: Measure Frame Dimensions

For each strip PNG:
- `frame_width` = total image width / frame count
- `frame_height` = total image height
- Verify all strips for a character share the same frame dimensions (required by the sprite system)

If frame dimensions differ across animations for the same character (common with boss sprites), the largest frame size must be used and smaller frames padded/centered.

### Step 2D: Create poses.json

Each sprite set gets a `poses.json` mapping animation names to pose IDs with timing and hitbox data:

```json
{
  "seed_version": 5,
  "poses": {
    "0": {
      "name": "idle",
      "dir": 1,
      "mvtype": 0,
      "y_radius": 16,
      "y_offset": 0,
      "collision_x": 0,
      "collision_width": 24,
      "hurtbox_x": 0,
      "hurtbox_y": -16,
      "hurtbox_w": 24,
      "hurtbox_h": 32,
      "weapon_anchor_x": 0,
      "weapon_anchor_y": -24,
      "timing": [10, 10, 10, 10],
      "loop_from": 0,
      "transition_to": -1
    },
    "1": {
      "name": "walk",
      "dir": 1,
      "mvtype": 1,
      ...
    }
  }
}
```

Pose ID conventions:
- 0 = idle/forward
- 1 = walk/run right
- 2 = attack
- 3 = hurt
- 4 = death
- 5-9 = character-specific (jump, crouch, special, etc.)

### Step 2E: Create player_frames.json

Maps each frame index to its pose and source sheet:

```json
{
  "frame_width": 64,
  "frame_height": 64,
  "sheet_cols": 1,
  "center_x": 32,
  "center_y": 32,
  "seed_version": 4,
  "frames": [
    { "pose": 0, "layers": [{ "sheet": "idle", "index": 0 }] },
    { "pose": 0, "layers": [{ "sheet": "idle", "index": 1 }] },
    ...
  ]
}
```

---

## 3. Entity Registry Entries

Each imported character gets an entry in `Content/demo/Entities/entities.json`:

### Enemy Template
```json
{
  "category": "enemy",
  "id": "bat_bridge",
  "name": "Bridge Bat",
  "description": "Flying bat enemy. Hangs from ceilings, swoops at players.",
  "scene": "res://Scenes/Enemy.tscn",
  "sprite_set": "Sprites/bat_bridge",
  "behavior": "bat_swoop",
  "hp": 5,
  "attack_damage": 1,
  "contact_damage": 1,
  "contact_cooldown": 0.8,
  "move_speed": 60.0,
  "projectile_damage": 0,
  "projectile_speed": 0
}
```

### Boss Template
```json
{
  "category": "boss",
  "id": "boss_demon",
  "name": "Demon Lord",
  "description": "Large demon boss with breath attack.",
  "scene": "res://Scenes/Enemy.tscn",
  "sprite_set": "Sprites/boss_demon",
  "behavior": "boss_demon_ai",
  "hp": 100,
  "attack_damage": 5,
  "contact_damage": 3,
  "contact_cooldown": 1.0,
  "move_speed": 30.0,
  "projectile_damage": 4,
  "projectile_speed": 120.0
}
```

### NPC Template
```json
{
  "category": "interactable",
  "id": "npc_old_woman",
  "name": "Old Woman",
  "description": "Town NPC. Set dialogue_id property.",
  "scene": "res://Scenes/NPC.tscn",
  "sprite_set": "Sprites/npc_old_woman"
}
```

---

## 4. Behavior Tree Designs

Each enemy archetype gets a Beehave behavior tree. Trees are authored in the behavior editor and saved to `behaviors.json`.

### 4A. Available Leaves (from beh_registry.gd)

**Actions:** idle, walk, walk_left, walk_right, jump, turn_around, attack, flee, pursue, patrol_point, shoot, dash

**Conditions:** always, wall_ahead, grounded, in_air, player_near, player_seen, edge_ahead, hp_low, cooldown_ready

### 4B. Behavior Archetypes

#### Archetype: Ground Patrol (`patrol_basic`)
*For: Skeleton, Mummy, Walking Skeleton, Swamp Thing, Death Lamp, Ogre (unarmed)*
```
sequence_star "main"
  selector "decide"
    sequence "chase"
      condition player_near (range: 120)
      action pursue
    sequence "patrol"
      selector "obstacle_check"
        condition wall_ahead
        condition edge_ahead
      action turn_around
  action walk
```

#### Archetype: Aggressive Melee (`melee_aggressive`)
*For: Ogre (armed), Werewolf, Doublesword, Long-sword, Hell Hound, Wolf*
```
selector "main"
  sequence "attack"
    condition player_near (range: 40)
    condition cooldown_ready (name: "atk", seconds: 0.8)
    action attack (damage: per-entity)
  sequence "chase"
    condition player_seen (range: 150)
    action pursue
  sequence "patrol"
    selector "turn"
      condition wall_ahead
      condition edge_ahead
    action turn_around
  action walk
```

#### Archetype: Ranged Attacker (`ranged_attacker`)
*For: Sorcerer, Wizard, Shotgun Skeleton, Shuriken Dude, Mage variants, Fire Skull*
```
selector "main"
  sequence "shoot"
    condition player_seen (range: 200)
    condition cooldown_ready (name: "shoot", seconds: 1.5)
    action shoot (aim: "player", speed: 180, damage: per-entity)
  sequence "kite"
    condition player_near (range: 60)
    action flee
  sequence "patrol"
    selector "turn"
      condition wall_ahead
      condition edge_ahead
    action turn_around
  action walk
```

#### Archetype: Flying Enemy (`flyer_basic`)
*For: Bat, Crow, Vulture, Flying Eye Demon, Ghost, Fire Skull (alt)*
```
selector "main"
  sequence "swoop"
    condition player_near (range: 100)
    action pursue
  sequence "wander"
    selector "turn"
      condition wall_ahead
    action turn_around
  action walk
```
Note: The MV engine currently grounds enemies via gravity. True flying enemies need velocity.y zeroed in a custom leaf or need the `in_air` condition to skip gravity. For now, these will use ground-based pursue/walk behavior as a functional stand-in.

#### Archetype: Stationary Attacker (`turret`)
*For: Spider (venom), Hell Beast, Boss Demon (breath)*
```
selector "main"
  sequence "ranged_attack"
    condition player_seen (range: 250)
    condition cooldown_ready (name: "spit", seconds: 2.0)
    action shoot (aim: "player")
  sequence "melee_fallback"
    condition player_near (range: 40)
    action attack
  action idle
```

#### Archetype: Jumper (`jumper`)
*For: Slime, Mutant Toad, Imp, Amphibean*
```
sequence_star "main"
  selector "decide"
    sequence "jump_attack"
      condition player_near (range: 100)
      condition grounded
      action jump
    sequence "chase"
      condition player_near (range: 150)
      action pursue
    sequence "patrol"
      selector "turn"
        condition wall_ahead
        condition edge_ahead
      action turn_around
  action walk
```

#### Archetype: Fleeing NPC (`coward`)
*For: Ghost (cemetery), Fox (unarmed)*
```
selector "main"
  sequence "run_away"
    condition player_near (range: 100)
    action flee
  action idle
```

#### Archetype: Boss Phase AI (`boss_phased`)
*For: Boss Dragon, Boss Wendigo, Boss Demon*
```
selector "main"
  sequence "rage_phase"
    condition hp_low (threshold: 0.3)
    selector "rage_actions"
      sequence "dash_attack"
        condition cooldown_ready (name: "dash", seconds: 3.0)
        action dash
      sequence "shoot_barrage"
        condition cooldown_ready (name: "shoot", seconds: 1.0)
        action shoot (aim: "player")
      action pursue
  sequence "normal_phase"
    selector "normal_actions"
      sequence "melee"
        condition player_near (range: 60)
        condition cooldown_ready (name: "atk", seconds: 1.5)
        action attack
      sequence "ranged"
        condition player_seen (range: 200)
        condition cooldown_ready (name: "shoot", seconds: 2.5)
        action shoot (aim: "player")
      sequence "approach"
        condition player_seen (range: 300)
        action pursue
  action idle
```

#### Archetype: Passive NPC (`npc_idle`)
*For: NPC Man, Old Woman, Town NPCs, Young Woman, Annette*
```
action idle
```
(NPCs use the NPC scene, not Enemy scene, so they don't need combat behavior. They only need idle animation.)

---

## 5. Detailed Per-Character Plan

### Group A: Standalone Packs (strips ready to use)

#### A1. Annette (`annette-sprites-v1`)
- **Role:** NPC / ally
- **Category:** `interactable`
- **Entity ID:** `npc_annette`
- **Sprite import:**
  - `spr_annette_idle_strip6.png` -> `idle.png` (6 frames)
  - `spr_annette_idle_unarmed_strip6.png` -> keep as variant
  - `spr_annette-running_strip8.png` -> `walk.png` (8 frames)
  - `spr_annette-magic1_strip4.png` -> `attack.png` (4 frames)
  - `annette-crouching_strip4.png` -> `crouch.png` (4 frames)
  - `spr_annette-crouch_strip1.png` -> single frame crouch
  - `annette-idle-sword-pose_strip4.png` -> `idle_armed.png` (4 frames)
- **Frame dimensions:** Measure from strip width / frame count
- **Behavior:** `npc_idle` (no combat AI — she's an NPC)
- **Stats:** N/A (NPC scene)

#### A2. Blue Mage Staff (`bluemagestaff-v3`)
- **Role:** Enemy mage
- **Category:** `enemy`
- **Entity ID:** `blue_mage`
- **Sprite import (from `/sprites/` folder, all strips):**
  - `blue-mage-staff-idle_strip12.png` -> `idle.png`
  - `blue-mage-staff-walk_strip4.png` -> `walk.png`
  - `blue-mage-staff-attack_strip3.png` -> `attack.png`
  - `blue-mage-staff-death_strip7.png` -> `death.png`
  - `blue-mage-staff-hithurt.png` -> `hurt.png`
  - `blue-mage-staff-jump_strip3.png` -> `jump.png`
  - `blue-mage-staff-special_strip10.png` -> `special.png`
- **Behavior:** `ranged_attacker` (shoot + kite + patrol)
- **Stats:** hp: 20, attack_damage: 2, move_speed: 45, projectile_damage: 3, projectile_speed: 160

#### A3. Double Sword Warrior (`doublesword-v7`)
- **Role:** Enemy melee
- **Category:** `enemy`
- **Entity ID:** `double_sword`
- **Sprite import:**
  - `double-sword-idle_strip6.png` -> `idle.png`
  - `double-sword-running_strip8.png` -> `walk.png`
  - `double-sword-attack_1_strip3.png` -> `attack.png`
  - `double-sword-die_strip8.png` -> `death.png`
  - `double-sword-hithurt.png` -> `hurt.png`
  - `double-sword-jump_strip2.png` -> `jump.png`
- **Behavior:** `melee_aggressive`
- **Stats:** hp: 25, attack_damage: 3, contact_damage: 1, move_speed: 55

#### A4. Long Sword (lite) (`long-sword-free-walk-attack1`)
- **Role:** Enemy melee (simple)
- **Category:** `enemy`
- **Entity ID:** `long_sword_lite`
- **Sprite import:**
  - `long-sword-walk_strip4.png` -> `walk.png`
  - `long-sword-attack_strip3.png` -> `attack.png`
- **Note:** Only 2 animations. Use walk frame 0 as idle fallback.
- **Behavior:** `patrol_basic` (limited anims = simple AI)
- **Stats:** hp: 15, attack_damage: 2, move_speed: 40

#### A5. Long Sword (full) (`long-sword-sprites-v5`)
- **Role:** Enemy melee (full)
- **Category:** `enemy`
- **Entity ID:** `long_sword`
- **Sprite import:**
  - `long-sword-idle_strip10.png` -> `idle.png`
  - `long-sword-running_strip8.png` -> `walk.png`
  - `long-sword-attack_strip3.png` -> `attack.png`
  - `long-sword-dying_strip4.png` -> `death.png`
  - `long-sword-hithurt_strip1.png` -> `hurt.png`
  - `long-sword-roll_strip7.png` -> `roll.png`
  - `long-sword-fall_strip7.png` -> `fall.png`
- **Behavior:** `melee_aggressive`
- **Stats:** hp: 30, attack_damage: 3, contact_damage: 1, move_speed: 50

#### A6. Legacy Vania NPCs (`legacy-vania-npc-v7`)
- **Role:** NPCs
- **Category:** `interactable`
- **Entity IDs:** Per character found in subfolder
- **Sprite import:** Enumerate sprites/spritesheets, create one entity per distinct character
- **Behavior:** `npc_idle`

### Group B: Boss Characters

#### B1. Boss Demon
- **Entity ID:** `boss_demon`
- **Category:** `boss`
- **Sprite import:**
  - Stitch `Sprites/demon-attack-no-breath[1-9].png` -> `attack.png` (9 frames)
  - Stitch `Sprites/DemonAttackBreath/demon-attack[1-18].png` -> `special.png` (18 frames)
  - Use `Spritesheets/demon-idle.png` -> `idle.png` (use as strip or stitch)
- **Behavior:** `boss_phased`
- **Stats:** hp: 150, attack_damage: 5, contact_damage: 3, move_speed: 25, projectile_damage: 6, projectile_speed: 100

#### B2. Boss Dragon
- **Entity ID:** `boss_dragon`
- **Category:** `boss`
- **Sprite import:**
  - Stitch `sprites/Idle/boss-dragon-idle[1-6].png` -> `idle.png`
  - Stitch `sprites/fly/fly[1-8].png` -> `walk.png`
  - Stitch `sprites/Fly-Attack/fly-attack[1-5].png` -> `attack.png`
  - Stitch `sprites/FireBreath/boss-dragon-firebreath[1-9].png` -> `special.png`
  - Stitch `sprites/Death/frame[1-11].png` -> `death.png`
- **Behavior:** `boss_phased` (with shoot for firebreath)
- **Stats:** hp: 200, attack_damage: 6, contact_damage: 4, move_speed: 35, projectile_damage: 5, projectile_speed: 140

#### B3. Boss Wendigo
- **Entity ID:** `boss_wendigo`
- **Category:** `boss`
- **Sprite import:**
  - Stitch `SPRITES/Idle/sprites/boss-wendigo-idle[1-4].png` -> `idle.png`
  - Stitch `SPRITES/Attack/sprites/boss-wendigo-attack[1-11].png` -> `attack.png`
  - Stitch `SPRITES/Run/Sprites/boss-wendigo-run[1-7].png` -> `walk.png`
- **Behavior:** `boss_phased`
- **Stats:** hp: 120, attack_damage: 7, contact_damage: 3, move_speed: 50

### Group C: Bridge Enemies

#### C1. Bat
- **Entity ID:** `bat_bridge`
- **Category:** `enemy`
- **Sprite import:**
  - Stitch `bat-flying/bat-flying-[1-4].png` -> `walk.png` (or use `Spritesheets/bat-fly.png`)
  - Stitch `bat-hang/bat-hang-[1-3].png` -> `idle.png` (or use `Spritesheets/bat-hang.png`)
- **Behavior:** `flyer_basic`
- **Stats:** hp: 3, attack_damage: 1, contact_damage: 1, move_speed: 70

#### C2. Bridge Skeleton
- **Entity ID:** `skeleton_bridge`
- **Category:** `enemy`
- **Sprite import:** Stitch `Sprites/skeleton-[1-6].png` -> `walk.png` (or use `spritesheet.png`)
- **Behavior:** `patrol_basic`
- **Stats:** hp: 10, attack_damage: 1, contact_damage: 1, move_speed: 30

#### C3. Sorcerer
- **Entity ID:** `sorcerer_bridge`
- **Category:** `enemy`
- **Sprite import:** Stitch `Sprites/sorcerer-[1-4].png` -> `idle.png` (or use `Spritesheet.png`)
- **Behavior:** `ranged_attacker`
- **Stats:** hp: 12, attack_damage: 1, move_speed: 20, projectile_damage: 2, projectile_speed: 150

### Group D: Cemetery Enemies

#### D1. Ghost
- **Entity ID:** `ghost_cemetery`
- **Category:** `enemy`
- **Sprite import:**
  - Stitch `Sprites/ghost-[1-4].png` -> `walk.png`
  - Use ghost-halo variant as `idle.png`
- **Behavior:** `flyer_basic`
- **Stats:** hp: 8, contact_damage: 1, move_speed: 40

#### D2. Hell Cat
- **Entity ID:** `hell_gato`
- **Category:** `enemy`
- **Sprite import:** Stitch `Sprites/hell-gato-[1-4].png` -> `walk.png`
- **Behavior:** `melee_aggressive`
- **Stats:** hp: 12, attack_damage: 2, contact_damage: 1, move_speed: 65

#### D3. Cemetery Skeleton
- **Entity ID:** `skeleton_cemetery`
- **Category:** `enemy`
- **Sprite import:**
  - Stitch `Sprites/Walk/skeleton-[1-8].png` -> `walk.png`
  - Stitch `skeleton-rise/skeleton-rise-[1-6].png` -> `spawn.png`
- **Behavior:** `patrol_basic`
- **Stats:** hp: 10, attack_damage: 1, contact_damage: 1, move_speed: 30

### Group E: Church Enemies

#### E1. Angel
- **Entity ID:** `angel_church`
- **Category:** `enemy`
- **Sprite import:**
  - Stitch `sprites/idle/*.png` -> `idle.png`
  - Stitch `sprites/angel-attack/*.png` -> `attack.png`
- **Behavior:** `melee_aggressive`
- **Stats:** hp: 20, attack_damage: 3, move_speed: 45

#### E2. Burning Ghoul
- **Entity ID:** `burning_ghoul`
- **Category:** `enemy`
- **Sprite import:** Use v2 variant sprites -> `walk.png`, `idle.png`
- **Behavior:** `patrol_basic` with melee
- **Stats:** hp: 18, attack_damage: 2, contact_damage: 2, move_speed: 35

#### E3. Wizard
- **Entity ID:** `wizard_church`
- **Category:** `enemy`
- **Sprite import:**
  - Stitch `idle-sprites/*.png` -> `idle.png`
  - Stitch `fire-sprites/*.png` -> `attack.png`
- **Behavior:** `ranged_attacker`
- **Stats:** hp: 15, attack_damage: 1, move_speed: 25, projectile_damage: 3, projectile_speed: 160

### Group F: Standalone Enemies (abbreviated — full list would repeat the same pattern)

Each follows the same process: stitch individual frames or copy strip PNGs, create poses.json, add entity, assign behavior archetype based on their capabilities.

Key examples:

| Entity ID | Behavior | Key Stats |
|---|---|---|
| `spider` | `turret` (venom projectile) | hp: 15, proj_dmg: 2 |
| `ogre_armed` | `melee_aggressive` | hp: 40, atk: 4 |
| `werewolf` | `melee_aggressive` | hp: 35, atk: 3, speed: 70 |
| `hell_hound` | `melee_aggressive` | hp: 20, atk: 2, speed: 80 |
| `hell_beast` | `turret` | hp: 50, proj_dmg: 4 |
| `mutant_toad` | `jumper` | hp: 15, atk: 2 |
| `fire_skull` | `flyer_basic` | hp: 8, contact: 1 |
| `shotgun_skeleton` | `ranged_attacker` | hp: 15, proj_dmg: 3 |
| `shuriken_dude` | `ranged_attacker` | hp: 18, proj_dmg: 2 |
| `nightmare_horse` | `melee_aggressive` | hp: 45, atk: 4, speed: 90 |
| `ghost_detailed` | `coward` (appear/vanish) | hp: 12, contact: 2 |

### Group G: Enemy Sprite Packs (72 packs)

These are the numbered packs in `enemy_sprites/`. Each contains 3-6 enemies as pre-made sprite strips. These are the easiest to import since they match the existing import format (similar to the `basement_enemies_pixel_art_sprite_pack_*` entries already in entities.json).

**Import process per pack:**
1. Enumerate numbered subfolders (e.g., `1/`, `2/`, `3/`)
2. In each subfolder, find PNGs (already horizontal strips with names like `attack.png`, `idle.png`, `walk.png`, `death.png`, `hurt.png`)
3. Copy to `Content/demo/Sprites/<pack_id>_<number>/`
4. Add entity entry to entities.json
5. Assign behavior based on pack theme

**Batch assignment table (72 packs):**

| Pack | Type | Behavior |
|---|---|---|
| basement-enemies (6) | melee+ranged mix | `melee_aggressive` / `ranged_attacker` |
| basement-bosses (3) | bosses | `boss_phased` |
| bar-street-enemies (6) | melee fighters | `melee_aggressive` |
| bar-street-bosses (3) | bosses | `boss_phased` |
| business-enemies (6) | melee | `melee_aggressive` |
| cave-monsters (6) | dungeon mix | varies per enemy |
| cave-bosses (3) | bosses | `boss_phased` |
| hell-monsters (6) | dungeon mix | varies |
| hell-bosses (3) | bosses | `boss_phased` |
| fire-monsters (6) | dungeon mix | varies |
| cyberpunk-desert-bandits (6) | ranged | `ranged_attacker` |
| cyberpunk-beach (6) | ranged | `ranged_attacker` |
| cyberpunk-bosses (3) | bosses | `boss_phased` |
| demon-sprites (3) | melee | `melee_aggressive` |
| desert-bosses (3+3) | bosses | `boss_phased` |
| dragon-sprites (3) | bosses | `boss_phased` |
| enemies-chinese-street (6) | melee | `melee_aggressive` |
| enemies-exclusion-zone (6) | ranged | `ranged_attacker` |
| field-bosses (3) | bosses | `boss_phased` |
| lab-enemies (6) | sci-fi mix | varies |
| lab-bosses (3) | bosses | `boss_phased` |
| mountain-monsters (?) | dungeon mix | varies |
| pirate-sprites (?) | ranged | `ranged_attacker` |
| pirate-bosses (3) | bosses | `boss_phased` |
| residential-enemies (?) | melee | `melee_aggressive` |
| residential-bosses (3) | bosses | `boss_phased` |
| robots (?) | ranged | `ranged_attacker` |
| ruin-enemies (?) | dungeon mix | varies |
| sewerage-enemies (?) | melee | `melee_aggressive` |
| sewerage-bosses (3) | bosses | `boss_phased` |
| snow-enemies (?) | ranged/melee mix | varies |
| snow-bosses (3) | bosses | `boss_phased` |
| space-pirates (?) | ranged | `ranged_attacker` |
| water-monsters (?) | dungeon mix | varies |
| mine-bosses (3) | bosses | `boss_phased` |
| industrial-bosses (3) | bosses | `boss_phased` |
| prison-bosses (3) | bosses | `boss_phased` |
| power-station (?) | sci-fi | varies |
| (civilian/vehicle/NPC packs) | non-combat | `npc_idle` |

### Group H: Playable Characters (repurposed as enemies or NPCs)

These characters have the richest animation sets. Import as high-tier enemies or ally NPCs:

| Character | Entity ID | Category | Behavior | Key Stats |
|---|---|---|---|---|
| Bridge Heroine | `heroine_bridge` | `enemy` | `melee_aggressive` | hp: 50, atk: 3, speed: 55 |
| Cemetery Hero | `hero_cemetery` | `enemy` | `melee_aggressive` | hp: 45, atk: 3, speed: 50 |
| Gun Slinger Girl | `gunslinger` | `enemy` | `ranged_attacker` | hp: 35, proj: 4, speed: 55 |
| Hooded Hero | `hooded_hero` | `enemy` | `melee_aggressive` | hp: 40, atk: 3, speed: 60 |
| Monk | `monk` | `enemy` | `melee_aggressive` | hp: 50, atk: 4, speed: 45 |
| Ninja Girl | `ninja_girl` | `enemy` | `melee_aggressive` | hp: 35, atk: 3, speed: 70 |
| Ninja Scroller | `ninja_scroller` | `enemy` | `melee_aggressive` | hp: 30, atk: 2, speed: 65 |
| Rifle Man | `rifleman` | `enemy` | `ranged_attacker` | hp: 30, proj: 3, speed: 45 |
| Terrible Knight | `terrible_knight` | `enemy` | `melee_aggressive` | hp: 55, atk: 4, speed: 40 |

### Group I: NPCs (non-combat)

| Character | Entity ID | Category |
|---|---|---|
| NPC Man | `npc_man` | `interactable` |
| Old Woman | `npc_old_woman` | `interactable` |
| Town NPC - Bearded | `npc_bearded` | `interactable` |
| Town NPC - Hat Man | `npc_hat_man` | `interactable` |
| Town NPC - Old Man | `npc_oldman` | `interactable` |
| Town NPC - Woman | `npc_woman` | `interactable` |
| Young Woman | `npc_young_woman` | `interactable` |
| Annette | `npc_annette` | `interactable` |

### Group J: Projectiles and FX

Shared death animations and projectile sprites need to be imported as FX entities:

| Entity ID | Source | Category |
|---|---|---|
| `fx_enemy_death_bridge` | Bridge Enemies/Enemy Death (5f) | `fx` |
| `fx_enemy_death_cemetery` | Cemetery Enemies/EnemyDeath (5f) | `fx` |
| `fx_enemy_death_church` | Church Enemies/fx/enemy-death (5f) | `fx` |
| `fx_fireball_bridge` | Bridge Enemies/FireballAttack (4f) | `fx` |
| `fx_fireball_church` | Church Enemies/fx/fireball | `fx` |
| `fx_spider_venom` | Spider/venom (all variants) | `fx` |
| `fx_shuriken` | Shuriken Dude/shuriken | `fx` |

---

## 6. Execution Order

### Phase 1: Infrastructure (prerequisites)
1. Create `behaviors.json` in `Content/demo/Behaviors/` with all behavior archetypes defined (8 trees)
2. Verify `import_pack.gd` tool handles the strip format from these asset packs
3. Confirm content_validator passes with the expanded entity list

### Phase 2: Easy Wins — Pre-stripped Enemy Packs (est. ~72 packs, ~350 entities)
1. Write a batch import script that:
   - Iterates `enemy_sprites/` packs
   - Copies numbered subfolder PNGs to `Content/demo/Sprites/<pack_id>_<n>/`
   - Auto-generates entity entries in entities.json
   - Assigns behavior by pack theme
2. Run the script
3. Spot-check 5-10 imported entities in the editor
4. Validate all via content_validator

### Phase 3: Strip-Ready Standalone Characters (est. 6 characters)
1. Copy strip PNGs from annette, bluemagestaff, doublesword, long-sword(x2), legacy-vania
2. Create poses.json for each (measure frame dimensions, assign timing)
3. Add entity entries
4. Test in playtest mode

### Phase 4: Individual-Frame Characters — Bosses (est. 3 bosses)
1. For each boss, stitch individual frames into strips using ImageMagick:
   ```bash
   convert +append frame1.png frame2.png ... strip.png
   ```
2. Verify frame dimensions are consistent across animations
3. Create poses.json with appropriate timing (bosses need slower, more deliberate animations)
4. Add entity entries with boss stats
5. Create boss-specific behavior trees (tuned cooldowns, phase thresholds)
6. Playtest each boss

### Phase 5: Individual-Frame Characters — Enemies (est. ~40 enemies)
1. Same stitch process as bosses
2. Prioritize by richness of animation set:
   - **Tier 1 (4+ anims):** Spider, Ghost-Files, Hell-Beast, Hell-Hound, Ogre, Werewolf, Mutant Toad, Ninja enemies
   - **Tier 2 (2-3 anims):** Bat, Skeleton variants, Sorcerer, Ghost, Hell Gato, Wizard, Crow, Fox
   - **Tier 3 (1 anim):** Walking Skeleton, Wolf, Mummy, Slime, Swamp Spider, Swamp Thing, Vulture, Meerman, Demon
3. Create poses.json per entity
4. Assign behaviors from archetypes

### Phase 6: Playable Characters as Enemies (est. 9 characters)
1. Select core animations per character (idle, run, attack, hurt, death — skip niche anims like climb, drink, meditation)
2. Copy strip PNGs, create poses.json
3. Add as high-tier enemies with boss-adjacent stats
4. These make excellent mini-bosses or special encounters

### Phase 7: NPCs (est. 8+ characters)
1. Copy idle + walk strips
2. Simple poses.json (just idle + walk poses)
3. Add as interactable entities with NPC scene
4. No behavior trees needed (NPC scene handles dialogue)

### Phase 8: Projectiles and FX (est. 7 fx entities)
1. Import death and projectile animations
2. Create minimal poses.json (single animation, no loop)
3. Add as `fx` category entities

### Phase 9: QA Pass
1. Open content editor, verify every entity appears in the list with correct category coloring
2. For each behavior, place one entity in a test room and playtest:
   - patrol_basic: walks, turns at walls/edges
   - melee_aggressive: chases, attacks, turns
   - ranged_attacker: shoots at range, flees up close
   - flyer_basic: pursues when near
   - turret: shoots from position
   - jumper: jumps toward player
   - boss_phased: phases at low HP
3. Validate sprite dimensions match across all animations per entity
4. Check for frame rate issues (timing values feel right)

---

## Totals

| Category | Count |
|---|---|
| Behavior archetypes | 8 |
| Boss entities | ~25 (3 unique bosses + ~22 from boss packs) |
| Enemy entities | ~300+ (72 packs x ~4 avg + ~40 individual) |
| NPC entities | ~30+ (8 unique + civilians from packs) |
| FX entities | ~7 |
| Playable-as-enemy | 9 |
| **Total new entities** | **~370+** |

## Tools Needed

- **ImageMagick** — `convert +append` for stitching individual frames into strips
- **Godot Editor** — content editor for verification, playtest mode for behavior testing
- **Python/GDScript** — batch import script for the 72 enemy_sprites packs (modify `import_pack.gd` or write standalone)
- **Content Validator** — `content_validator.gd` to verify all entries after import

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Frame size mismatch across animations | Sprite rendering breaks | Measure all strips before import; pad smaller frames to match largest |
| Flying enemies lack gravity bypass | Flyers walk on ground | Document as known limitation; add `fly` action leaf later |
| 370+ entities overwhelm editor list | Editor performance | Existing category filter helps; consider pagination if needed |
| Boss behavior too simple with current leaves | Bosses feel generic | Phase-based AI helps; add new leaves (teleport, summon) later |
| Batch import produces wrong frame counts | Animations play wrong | Validate strip width divisibility by expected frame count |
