# Content Pack Change

## Goal

Describe the pack data, schema, or sample content change.

## Affected Pack Areas

- Rooms:
- Entities:
- Dialogue:
- Triggers:
- Shops:
- Items/equipment:
- Player stats/attacks/projectiles:
- UI screens:
- Assets:

## Required Path

Pack JSON -> loader -> validation -> editor round-trip -> runtime behavior.

## Acceptance Criteria

- User pack path and shipped pack fallback still work.
- Demo or golden content exercises the new path.
- Invalid references fail validation.
- Import docs are updated when layout or asset conventions change.

