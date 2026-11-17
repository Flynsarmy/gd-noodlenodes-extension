---
name: godot
description: Run, import, test and export this Godot project from the command line using the locally installed Godot 4.7.2 editor binary. Use for headless runs, the GUT test suite, GDScript syntax checks and asset imports.
---

## Engine

This project targets **Godot 4.7.2** (`api_version=4.7`). Godot is installed through Godot Version Manager and is **not on `PATH`** — never call a bare `godot`.

Binary (path contains spaces, always quote it):

```
$HOME/Library/Application Support/Godot/app_userdata/Godot Version Manager/versions/Godot_v4.7.2-stable.app/Contents/MacOS/Godot
```

## Wrapper

`scripts/godot` next to this file resolves the binary and forwards all arguments. From the repo root:

```sh
GODOT=.agents/skills/godot/scripts/godot
"$GODOT" --version   # 4.7.2.stable.official
```

`GODOT_VERSION=4.6.3 "$GODOT" ...` picks another installed version. Don't do this for this project unless asked.

## Build and test

```sh
scons platform=macos                         # builds template_debug into demo/addons/noodle_nodes/bin
"$GODOT" --headless --path demo --import --quit
"$GODOT" --headless --path demo -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://test/ -gprefix=test_ -gsuffix=.gd -gexit -ginclude_subdirs
```

Narrow to matching files with `-gselect=test_parallel` (substring match on file name) instead of the whole suite while iterating; run the full suite before reporting done.

## Gotchas

- `--check-only` returns exit code 0 even on parse errors. Grep the output for `Parse error` / `Failed to load script`.
- Run `--import` after adding assets or scripts from the shell, or new `class_name`s and resources won't resolve.
- Rebuild with scons after any `src/` change; Godot loads the compiled library, not the source.
