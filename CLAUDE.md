# Working on this repository

Notes for anyone — person or agent — picking this up. Everything here cost
time to learn once already.

## Do not overwrite Victor's edits

This is the rule that matters most, because breaking it destroys work rather
than merely wasting time.

An agent session edits a **copy** of this repository in a cloud container and
writes changed files back to `C:\Users\victor\src\cartographer` with
`device_commit_files`. That call is a **blind overwrite**. It does not merge,
it does not warn, and it does not care that the file on disk is newer than the
copy being written. So an edit made on the real machine between one sync and
the next is simply gone, with nothing in git to recover it, because it was
never committed.

Three things prevent that, and all three are cheap:

1. **Read the working tree before writing to it.** `git status --porcelain` in
   the repository, every time, before any `device_commit_files`. A file listed
   there has changes that are not in git. Stage it
   (`device_stage_files`), read it, and merge — do not push over it.
2. **Pass `expectedMtimeMs`.** `device_stage_files` returns the file's
   modification time; handing that back to `device_commit_files` makes the
   call *refuse* to write if the file changed in between. That is what the
   parameter is for. Use it for every file that already exists.
3. **Commit first, then ask for changes.** A committed edit is recoverable
   even if it is overwritten (`git checkout <sha> -- <file>`, or just read the
   diff). An uncommitted one is not. If there are local edits in flight, say
   so, or commit them, before asking for work on the same files.

The failure mode looks like this from the outside: you change a label, ask for
something unrelated, and your change is gone with no error and no diff. If
that happens, `git log -p -- <file>` will show whether the edit ever reached a
commit; if it did not, it is lost.

## The project's own traps

**`--script` runs before autoloads exist.** A script passed to `godot
--script` is compiled before the project's autoloads are registered as
GDScript globals, so it cannot name `Platform`, `GameState`, `EventBus`,
`AlbumService` or `CCLog`. The pattern everywhere in `tools/` and `tests/` is a
thin `SceneTree` entry point that loads a `Node` script which does the work —
see `tests/run_tests.gd` plus `tests/test_host.gd`.

**Tests that build nodes need a live tree.** During `SceneTree._initialize()`
the root `Window` is not inside the tree: `_ready` never fires,
`global_transform` returns the identity, and `add_child` on the root fails.
`tests/test_host.gd` adds a host node and awaits one `process_frame` first.
Without that a suite can pass while testing nothing.

**Look at anything visual before calling it done.** Four rendering bugs and
every character bug in this project were invisible in the numbers and obvious
in a picture. `tools/render_shots.gd`, `render_hospital.gd`, `render_ending.gd`
and the `diag_*` tools run headless under xvfb with software GL.
`tools/draw_canvases.gd` and `tools/draw_embrace.gd` render the drawn figures
**flat**, one pixel per canvas pixel — the 3D renders hid four drawing bugs
that the flat ones showed immediately.

**A UI built in code still has a layout budget.** The editor's detail column is
about 320 px wide on a 1024-wide window and its horizontal scrolling is off, so
anything wider is unreachable rather than merely cramped. That is an
invariant, and `tests/test_editor_screen.gd` asserts it with
`get_combined_minimum_size()`, which needs no window and no frame.

**Never let a test document a bug.** Two tests in here asserted broken
behaviour and so hid it: one expected `cancel_guessing()` to drop to
`GALLERY_IDLE` (which left the E key dead) and then quietly put the state back
by hand; another expected a programmatic map pin to emit `pin_moved` (which was
overwriting the author's coordinates). If a fix makes a test fail, decide which
of the two is wrong and write down why next to the change.

## Running it

```
godot --path .                                     # play
godot --headless --path . --script tests/run_tests.gd   # ~1300 assertions, ~22 s
tools\run_tests.bat                                # same, on Windows
xvfb-run -a godot --path . --script tools/run_diag_editor.gd   # look at a screen
```

The suite is pure and headless: no window, no GPU. If it needs either, it is
in the wrong file.
