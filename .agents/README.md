# SpaceboatMania Agent Workflow

This directory defines the project-local agent system for keeping SpaceboatMania work clean, parallel, and easy to verify.

Use `.claude/agents/*.md` as executable Claude Code subagent prompts. Use this directory as the human-readable playbook and task template library.

## Operating Model

Every non-trivial change should move through this path:

1. Explorer maps the relevant code and data flow.
2. Coordinator splits the work into bounded ownership lanes.
3. One or more worker agents implement isolated slices.
4. Validation or reviewer agent checks contract drift and silent fallback.
5. Smoke test agent verifies the affected workflow.
6. Docs sync agent updates the repo contract when behavior changes.

For this repo, a feature is not complete until the editor, JSON pack data, validation, runtime behavior, and docs agree.

## Default Agent Set

- `coordinator`: plans slices, assigns ownership, integrates results.
- `codebase-explorer`: read-only mapping of files, call paths, and data paths.
- `space-runtime`: owns Space-side runtime behavior under `Space/scripts/**`.
- `mv-runtime`: owns MV-side runtime behavior under `MV/scripts/**`.
- `editor-suite`: owns content editor save/load/UI authoring code under `Space/scripts/editor/**`.
- `validation-contract`: owns validation, feature support contracts, and no-silent-fallback checks.
- `ui-runtime`: owns authored screen runtime, bindings, actions, and host mounting.
- `content-pack`: owns pack schemas, sample content, imports layout, and golden content.
- `entity-ai`: owns entities, behavior tree leaves, enemy stats, contact/projectile behavior.
- `asset-import`: owns import tooling and sprite/tileset ingestion workflows.
- `godot-scene-resource`: owns scene/resource wiring, `.tscn`, `.tres`, autoloads, and project settings.
- `code-reviewer`: reviews changed code for regressions, risky assumptions, missing validation, and maintainability.
- `smoke-test`: owns manual/headless validation and smoke reports.
- `docs-sync`: owns `CLAUDE.md`, `ROADMAP.md`, `SUPPORTED_FEATURES.md`, `IMPORTS.md`, and `TESTING_GUIDE.md` consistency.

## When To Use Multiple Agents

Use at least three agents for any feature that touches authored data:

- `codebase-explorer`
- one implementation worker
- `validation-contract`, `code-reviewer`, or `smoke-test`

Use five or more agents when a change crosses editor save, JSON, validation, runtime, and docs.

## Project Rules Agents Must Enforce

- Silent fallback is a bug.
- Null-bound UI is a bug.
- Validation failures are blockers.
- `SUPPORTED_FEATURES.md` is authoritative for authored UI support.
- If the editor exposes a feature, runtime must support it or validation must reject it.
- Content should round-trip through editor save, pack JSON, validation, pack load, and runtime behavior.
- Do not revert unrelated user changes in a dirty worktree.

## Task Templates

Use the files in `task-templates/` when assigning work:

- `feature-vertical-slice.md`
- `bug-investigation.md`
- `validation-change.md`
- `authored-ui-change.md`
- `content-pack-change.md`
- `smoke-test-report.md`
