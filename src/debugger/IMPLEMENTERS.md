You are one of several parallel implementers building the new Noodle Nodes debugger (Godot 4.7 GDExtension, C++ godot-cpp + GDScript). Other agents work on other parts at the same time in their own checkouts, so stay strictly inside the files you own (listed below). If you believe a file outside your ownership must change, make the smallest possible change and call it out explicitly in your final report.

## Read first
1. `AGENTS.md`: follow it exactly. No legacy shims, update `doc_classes/*.xml` for every bound API change, minimal comments (only non-obvious *why*), focused diffs, `.clang-format` for C++, quality-over-quantity tests that would fail if the feature broke, one-line imperative commit messages under 72 chars with no body and no trailers.
2. `src/debugger/PROTOCOL.md`: **the contract**. Snapshot schema, event kinds, the `NoodleNodesDebugger` singleton API, the EngineDebugger messages, the view interface and the file layout. Implement against it exactly. If the contract is wrong or missing something you need, make a minimal, sensible extension, keep the fixtures consistent, and list every deviation in your report.
3. `demo/test/unit/debugger/fixtures/debugger_fixtures.gd`: realistic snapshots/events for every root type (modelled on `demo/demo_08_integrated_npc`). `demo/addons/noodle_nodes/debugger/protocol.gd`, `status_palette.gd` and `demo/addons/noodle_nodes/editor/views/debug_view.gd` are shared helpers. Use them and don't fork them.

## Hard rule: UI is .tscn + GDScript
All debugger UI (the editor debugger tab, its shell, every system view, the in-game overlay, the NQS debug draw) is built as `.tscn` scenes with GDScript. Lay out the UI in the scene files: node hierarchy, containers, theme overrides, `%UniqueName` nodes. Scripts handle behaviour only and never build whole layouts in code. Small dynamic pieces (graph nodes, list rows, tree items) may be created at runtime, ideally by instancing small `.tscn` templates. C++ covers only the runtime side: snapshot/event API, ring buffers, registry, EngineDebugger transport, pause/step. Editor-side scripts are `@tool`. Write `.tscn` files by hand in valid Godot 4 text format (`[gd_scene format=3]`, `[ext_resource ...]`, `[node ...]`); omit `uid=` attributes rather than inventing them, or let the import step generate them. Then load and instantiate every scene headless to prove it parses.

## Environment
- Your checkout is a git worktree branched from the integration branch `debugger-tooling`. Work and commit on your own branch there. Don't push, don't touch `master` or `debugger-tooling`, and don't open PRs.
- If `godot-cpp/` is empty, run `git submodule update --init --recursive`.
- Build: `scons platform=macos -j10`. The first build compiles godot-cpp and takes a while. C++ work must also compile in release: `scons platform=macos target=template_release -j10`.
- Godot is not on PATH. Use `.agents/skills/godot/scripts/godot` (see `.agents/skills/godot/SKILL.md`). After adding scripts/scenes run `.agents/skills/godot/scripts/godot --headless --path demo --import` once.
- Full test suite (must be green before you finish, baseline is 723 passing): `.agents/skills/godot/scripts/godot --headless --path demo -d -s addons/gut/gut_cmdln.gd -gdir=res://test/ -gprefix=test_ -gsuffix=.gd -gexit -ginclude_subdirs`
- Never edit `godot-cpp/` or `demo/addons/gut/`.

## Quality bar (you will be reviewed on this)
- Complete against your brief and the contract, not a skeleton.
- Correct: ObjectIDs/instance ids are never dereferenced without resolving through ObjectDB / `is_instance_id_valid`; freed roots and nodes are harmless; no per-frame work when nobody is watching; debug-only code under `DEBUG_ENABLED`; release build compiles.
- Elegant: fits existing patterns, no duplication, no dead code, no speculative options.
- Tests: GUT tests under `demo/test/unit/debugger/` (extend existing files where they exist), testing observable behaviour. UI scenes are instantiated headless and driven with fixtures.

## Final report (your last message)
Branch name and final commit SHA; what you built (files); deviations from the contract and why; anything incomplete or deferred; exact test totals from the full suite run; release build result if you touched C++.
