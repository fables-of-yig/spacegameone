# Validation Change

## Goal

Describe the invalid data or unsupported feature that must be rejected or diagnosed.

## Contract Source

List the relevant contract file or runtime behavior:

- `SUPPORTED_FEATURES.md`
- `ROADMAP.md`
- runtime host/action matrix
- pack schema

## Required Checks

- Field existence:
- Type/range:
- Cross-reference:
- Host/action support:
- Runtime fallback prevention:

## Acceptance Criteria

- Invalid data is rejected before save or load.
- Error messages name the bad field and reference.
- Runtime no longer silently substitutes placeholder behavior.
- Docs updated if the supported contract changes.

