# Authored UI Change

## Goal

Describe the authored UI behavior being added or fixed.

## Affected Hosts

List affected hosts:

- `hud`
- `pause`
- `main_menu`
- `inventory`
- `map`
- `shop`
- `dialogue_box`
- `game_over`
- `boss_intro`

## Required Path

Editor control -> saved screen JSON -> validation -> `AuthoredScreenRuntime` -> host action/binding.

## Acceptance Criteria

- Editor exposes only supported options.
- Validation rejects unsupported binding/action/target combinations.
- Runtime renders visible diagnostics for unresolved live data.
- `SUPPORTED_FEATURES.md` is updated if support changed.

