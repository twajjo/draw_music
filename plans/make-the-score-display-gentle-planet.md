# Add the score-paper, top-bar and import items to the Phase 8 plan

## Context
The user wants these items added to the project plan (`plans/draw-music-plan.md`, Phase 8 section, and the PR list and design sections in `plans/phase-8-midi-input.md`):
1. **Score paper is its own setting**, not tied to the UI theme. It is a user default with a per-composition override.
2. **A prominent Settings button** in the top bar next to New and Compositions. The account menu's "Settings" is renamed to show that it's account setup.
3. **The Save button and its dropdown move to the top menu bar.**
4. **Import .mid can be reached from outside the Compositions page.**

**The "stash":** `git stash list` is empty. The repo is jj-colocated. The plan edits the user wants to keep are already in the jj working-copy change `wxlxnyqr`, on top of `Phase-7` (`13407ee`, already pushed). So there's nothing to pop: `Phase-7` is untouched, and these edits go into `wxlxnyqr`. Tell the user this rather than running any git or jj command.

This task edits the two plan documents only. No code changes.

## Edits to `plans/phase-8-midi-input.md`

### PR table (replace rows 8.1–8.3 and renumber)
| PR | Contents |
|---|---|
| 8.1 | Fix: dropdown menus close on click-away and Escape (unchanged) |
| 8.2 | Top bar: a **Settings** page for score display; the account menu's "Settings" becomes **Account** |
| 8.3 | Score paper: a user default, independent of the UI theme |
| 8.4 | Score paper: a per-composition override |
| 8.5 | The Save menu moves to the top bar (after 8.1, which fixes the dropdown it uses) |
| 8.6 | Import .mid from the top bar |
| 8.7 | The wordmark opens About (was 8.3) |
| 8.8–8.24 | The old 8.4–8.20, renumbered |

Update the "8.4–8.7" sweep note to "8.8–8.11", and in `draw-music-plan.md` change the "PR 8.2", "PR 8.3" and "Phase 8 is 20 such PRs" references to 8.3/8.4, 8.7 and 24.

### Rewrite "Score paper separate from the interface theme"
Replace the current design, which has a `:theme` option defaulting to Follow theme. The user has now ruled that out: the theme and the score are unrelated.
- **The user default:** a new `users.score_paper` field, an `Ecto.Enum` of `[:light, :dark]` with default `:light` (black on white). It's cast in `User.preferences_changeset`. Existing users who now see a black score under a dark theme will see white until they choose Dark; say so in the PR description.
- **The composition override:** a new `compositions.score_paper` field, `Ecto.Enum` `[:light, :dark]`, nullable, where nil means "use my default". It's cast in `Composition.changeset`, so the Details dialog, Save as and draft first save carry it with no extra plumbing (`store_details` in `editor_live.ex`).
- **The paper in use:** a pure function, e.g. `Layouts.score_paper(scope, composition_or_nil)`, returns the composition's value, else the user's, else `:light`. `Layouts.app` gets an optional `score_paper` attr. The editor passes `@composition.score_paper`, and other pages (help) use the user's default. The result is put on `<main class="score-colors">` as `data-score-paper`.
- **The CSS** (`assets/css/app.css`): `.score-colors` keeps the light tokens. `[data-theme=dark] .score-colors` becomes `.score-colors[data-score-paper=dark]`, which still uses `var(--score-ink-dark, #fff)`. The selection and playhead colours go with the paper. Nothing about the score reads `data-theme` any more.
- **The ink:** the composition overrides only the paper. Colour on black always uses the user's `score_ink_dark`.
- **The controls:**
  - a `paper_toggle` (Light / Dark) in `SettingsComponents` on the new Settings page, saved through a `set_score_paper` clause in `ScorePreferences.apply_event/3`;
  - a "Score paper: My default (Light) / Light / Dark" select in `LibraryComponents.composition_fields`, shown in the Details dialog and in Save as.
- **The exports:** SVG/PDF stay black on white (`score_export.ex` hard-codes `#fff`/`#000`). They are unchanged.
- **The cheat sheet:** a line saying where the paper default and override live.
- **Tests:** the user changeset accepts light/dark and refuses others; the composition changeset accepts nil/light/dark; `score_paper/2` resolves override, then default; the editor's `main` carries the right `data-score-paper` for each case; `set_score_paper` saves. The user checks dark UI with white paper, and light UI with dark paper, in the browser.

### New section: "Settings in the top bar, Account in the menu" (8.2)
- **A new `DrawMusicWeb.SettingsLive` at `/settings`**, placed in the existing `live_session :require_authenticated_user`, because preferences belong to a signed-in user. Its sections:
  - Score display: the layout toggle, plus the paper toggle and ink picker once 8.3 lands;
  - later, the Phase 8 `midi_length` preference.

  It reuses `ScorePreferences.form/1` and `apply_event/3`.
- **The top-bar nav in `Layouts.app`:** New, Compositions, **Settings** (`#nav-settings`), all styled the same way.
- **The account menu:** "Settings" becomes **Account** (`#account-menu-account`, `hero-user-circle` icon) and still links to `/users/settings`. That page keeps only email and password. Its "Score display" section moves to `/settings`, so its `set_score_*` handler goes too. The UI theme toggle stays where it is now, in the account menu.
- **Tests:** the nav has `#nav-settings`; `/settings` renders the layout toggle and saves a change; the account page no longer has `#score-display`.

### New section: "Save in the top bar" (8.5)
- `Layouts.app` gets a `:menu_bar` slot, rendered in the header nav after Settings. That keeps it within the LiveView, so `save`, `save_new_version` and `open_save_as` still reach `EditorLive`.
- `EditorLive.render/1` moves `<.save_menu>` from the palette's `:trailing` slot into `<:menu_bar>`, with the Unsaved badge beside it. The ids don't change, so Ctrl+S and the tests keep working.
- **Tests:** `#save-menu` (the existing id) is inside the header, not the palette.

### New section: "Import .mid from the top bar" (8.6)
- A top-bar **Import** link (`#nav-import`, `hero-arrow-up-tray`) points to a new `/compositions/import` route. It's a second live action, `:import`, of `LibraryLive`, in the same `live_session :require_authenticated_user` as `/compositions`.
- `handle_params` for `:import` opens the existing import dialog (`import_step: :upload`). Closing it patches back to `/compositions`.
- The upload code stays where it is, so there's no LiveComponent and no duplication.
- Leaving the editor follows the same rules as New.
- **Tests:** `/compositions/import` mounts with the upload dialog open; `#nav-import` is in the header.

## Edits to `plans/draw-music-plan.md`
- In Phase 8, replace the "Score paper separate from the interface theme" bullet with a short summary of the new design (user default plus composition override; no Follow theme) pointing to PRs 8.3/8.4.
- Add three bullets, each "requested 2026-11-06", that summarise and point to the new sections: Settings in the top bar with Account in the menu (8.2), Save in the top bar (8.5), and Import from the top bar (8.6).
- Renumber the About reference to 8.7, and change "Phase 8 is 20 such PRs" to 24.
- Under Phase 12's user-guide topics, add: "Score paper: your default in Settings, a composition's own in Details".

## Verification
- Run `jj diff --stat` to confirm that only `plans/draw-music-plan.md` and `plans/phase-8-midi-input.md` changed in `wxlxnyqr`, and that `Phase-7` is untouched (`jj log -r Phase-7`).
- Grep the plans for stale references: `Follow theme`, `PR 8.2`, `8.4–8.7`, `20 such PRs`.
