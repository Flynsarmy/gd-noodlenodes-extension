# Noodle Nodes

Godot 4.7 GDExtension (C++, godot-cpp) providing utility AI, behaviour trees, state trees and a node query system. Source in `src/`, class reference in `doc_classes/`, demo project and GUT tests in `demo/`.

## Environment

- Godot **4.7.2**, `api_version=4.7`. Godot is not on `PATH`. Use `.agents/skills/godot/scripts/godot` (see the `godot` skill).
- Build: `scons platform=macos`
- Test: `.agents/skills/godot/scripts/godot --headless --path demo -d -s addons/gut/gut_cmdln.gd -gdir=res://test/ -gprefix=test_ -gsuffix=.gd -gexit -ginclude_subdirs`
- Never edit `godot-cpp/` (submodule) or `demo/addons/gut/` (vendored).

## Project rules

- The project has no users yet. Do not keep legacy behaviour, compatibility shims or deprecations. Change the design, then update docs, demos, tutorials and tests to match.
- Any change to bound methods, properties, signals or enums updates `doc_classes/*.xml` in the same change.
- Keep diffs focused. No unrelated refactors, renames or reformatting. Follow `.clang-format`.
- Before reporting work done, rebuild and run the full suite. If other branches are in flight, rebase on current `master` first.

## Tests: quality over quantity

- Every test must protect something real: a bug that happened, documented behaviour, or a contract other code relies on. Ask: would this fail if someone broke the feature in a plausible way? If not, don't write it.
- A bug fix gets one regression test that fails without the fix. Check that it does.
- Test observable behaviour through the public API. Don't assert internals or values copied from the implementation (e.g. that an enum constant equals 2).
- Extend the existing test file for the feature before creating a new one. Reuse helpers instead of redefining them.
- When behaviour changes, rewrite or delete the tests for the old behaviour. Don't add workarounds to keep them passing.
- Prefer a few tests covering meaningful cases over exhaustive permutations.

## Comments: minimal

- Default to no comment. Good names and small functions come first.
- Only comment to explain *why* something non-obvious is done: an engine quirk, a lifetime or ordering constraint, a deliberate trade-off. One line where possible.
- Never restate what the code does, narrate the change ("now uses X instead of Y"), or refer to history ("previously", "historical behaviour").
- No commented-out code. Delete it; git has it.
- API documentation belongs in `doc_classes/`, not in source comments.

```cpp
// Bad
// Loop over every child and tick it, storing the result in the results array
// so that we can check the policy afterwards. This was changed to fix a bug.
for (...)

// Good
// SceneTree signals, not _process: a script overriding _process would silently stop ticks.
```

## Commits

- One line, imperative mood, under 72 characters, no body.
- Concise but descriptive: say what changed and why it matters, not how.
- No `Co-Authored-By` or other attribution trailers.
- Only commit when asked.

Good: `Fix NNBTParallel forgetting child failures between ticks`
Bad: `Update parallel.cpp`, `Fix bug`, `Refactor`
