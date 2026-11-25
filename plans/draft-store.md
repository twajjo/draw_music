# Unsaved work survives a reload

A reload, an accidental close-and-reopen, or the browser's Back and Forward
must not lose unsaved work. Today the main page always opens a new blank
draft, and a saved version always opens as saved, so any unsaved edits
are gone.

## Decisions (2026-11-25)

- **In memory, on the server:** an ETS table owned by a supervised
  process. A server restart (a deploy, restarting the dev server) loses the
  drafts, and that is accepted: it is not the user's doing. The user is
  protected from losing work through their own actions.
- **No database table:** nothing to clean up, and the library holds only
  what the user saved.
- **Not the browser session:** the cookie holds about 4 KB, and a LiveView
  can't write it after mount.
- **Key:** the user and the page: `{user_id, :new}` for the main page,
  `{user_id, {:version, version_id}}` for a saved version with unsaved edits.
- **Entry:** the editor's whole state: the `Session` (score, settings,
  selection, undo and redo), the version extras (instrument and the like),
  and the composition details shown in the header.
- **Lifetime:** written after every change that makes the editor dirty.
  Removed on save, on discard, and when nothing is left unsaved. An entry
  idle for a day is swept out.
- **Two tabs on one page:** the latest write wins.
- The "unsaved changes" warning before leaving stays as it is.

## PRs

1. **`DrawMusic.Drafts`, the store:** a GenServer owning the ETS table
   (writes go straight to ETS, so a long score isn't copied through the
   process), with `put/2`, `fetch/1` and `delete/1`, plus an hourly sweep
   of idle entries. Added to the application's supervision tree. Tests:
   put/fetch/delete, and the sweep.
2. **The editor keeps its draft:** `EditorLive` writes the draft after
   each change (edits, undo/redo, Score settings, details, instrument) and
   removes it on save or discard; on mount, it resumes a draft found
   under its key. Tests: change, remount (a reload), and the change is
   there; save, remount, and the draft is gone.
3. **Say so:** on resuming, a flash says unsaved changes were restored,
   with a way to discard them and start fresh. A cheat-sheet note (and a
   topic for the user guide).
