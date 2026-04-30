# Feature Vertical Slice

## Goal

State the single behavior being added or changed.

## User-Facing Behavior

Describe what a creator/player can now do in the editor or runtime.

## Expected Path

Editor save -> JSON -> validation -> pack load -> runtime behavior -> smoke test -> docs.

## Assigned Agents

- Explorer:
- Editor worker:
- Runtime worker:
- Validation worker:
- Content worker:
- Smoke test:
- Docs sync:

## Ownership Boundaries

List which files or directories each worker may edit.

## Acceptance Criteria

- Authored data changes live behavior without script edits.
- Bad references fail validation or produce visible diagnostics.
- No silent fallback is introduced.
- Runtime/editor contract is updated when support changes.
- Smoke checklist covers the affected path.

## Report Back

- Files changed.
- Behavior added.
- Validation added.
- Tests or smoke checks run.
- Remaining risks.

