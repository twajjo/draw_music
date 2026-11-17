# Preferences saved explicitly (Phase 8, 8.2b)

Requested 2026-11-15: saving preferences is explicit, never implied. Changes
preview live while the form is open; **Save** stores them, **Cancel** reverts
the preview, **Defaults** fills in the default values (still needing Save).
The panel can only be left by Save or Cancel.

## Now
- The Preferences panel (over the editor, `?panel=preferences`) and the
  `/users/preferences` page show the same sections
  (`PreferencesComponents.preference_sections/1`):
  - **Appearance:** the light / dark / system theme (`Layouts.theme_toggle`,
    kept in the browser's localStorage, not on the server);
  - **Score display:** the layout (`LayoutToggle`) and the dark-mode ink
    (`InkPicker`, swatches and a custom colour, refused if too dark);
  - **Reading aids:** three switches (`PreferenceSwitch`).
- Each of those components saves itself the moment it changes
  (`Accounts.update_user_preferences/2`) and sends `{module, {:updated, user}}`;
  `EditorLive` and the page put the user in their scope.
- The panel closes on its X, Esc, or a click outside.
- Outside the panel, two controls change preferences at once too: the
  palette's **Page / Strip** buttons (another `LayoutToggle`) and the
  account menu's light/dark switch (`theme_toggle`). See question 1.

## The design
- **One form:** a new LiveComponent `DrawMusicWeb.PreferencesForm`, used by the
  panel and the page. It holds a changeset of the user's preferences
  (`User.preferences_changeset/2`) as its form (`to_form`), with the layout,
  the ink, and the reading aids as fields. The ink picker and the switches
  become function components inside it (fields, no saving of their own);
  `InkPicker` and `PreferenceSwitch` go.
- **Live preview:** on every change (`phx-change`), the form validates and,
  when valid, sends `{PreferencesForm, {:preview, user}}`: the user with the
  changes applied, not stored. The LiveView puts that user in its scope, so the
  editor behind the panel redraws in the new layout, ink and aids. An invalid
  ink shows its error and isn't previewed.
- **Save** stores the changes (`Accounts.update_user_preferences/2`) and sends
  `{:saved, user}`; the panel closes.
- **Cancel** sends `{:cancelled, user}` with the stored user; the preview is
  undone and the panel closes.
- **Defaults** fills the form with the default values (those of a new `User`:
  strip layout, white ink, the reading aids' defaults) and previews them;
  nothing is stored until Save.
- **Leaving:** the panel loses its X, Esc and click-outside closing; Save and
  Cancel are the only ways out. It sits over the whole page, so the header's
  links can't be reached while it's open.
- **The page** (`/users/preferences`) has the same form, Save, Cancel and
  Defaults. Save and Cancel both leave the page, back to where it was opened
  from (a `return_to` path the account menu's link carries; the compositions
  page if there is none): Save keeps the changes, Cancel discards them.
  Leaving the page any other way with unsaved changes asks first (the editor's
  unsaved guard).
- **EditorLive:** its three `{module, {:updated, user}}` clauses become one
  `{PreferencesForm, {_preview_saved_or_cancelled, user}}` clause: put the user
  in the scope, lay the score out again if the layout changed, redraw the
  pieces if the reading aids changed, and nothing more for the ink (read when
  drawn).

## View choices in the editor (decided 2026-11-15)
The score's **layout** (page / strip) and its **paper** (black on white, or
colour on black) are view choices:
- The preferences are the user's preferred settings: what new and opened
  compositions start with.
- In the editor they can be switched for the session (the palette's Page /
  Strip buttons, and a paper toggle beside them), for any reason, without
  touching the preference. A switch lasts while the editor is open.
- They mean nothing for an individual composition: nothing is stored with it.
  (8.4, the per-composition paper override, is dropped.)
- The paper is the browser's view only. Every export (SVG, and printing from
  it) is black on white, as printed sheet music.
- The **UI theme** (light, dark, system) is a different thing: the
  application's look, not the score's. It is changed only in the Preferences
  form; the account menu's light/dark switch goes.

## PRs
1. **The form** (this plan's design, without the theme): `PreferencesForm`,
   the ink and switch fields, the panel and page using it (the page's Save and
   Cancel leave it), `EditorLive` and the page following its messages, the
   cheat sheet. About 10 files.
2. **Appearance in the form:** the theme becomes a form field too, previewed in
   the browser (a colocated hook sets `data-theme`), written to localStorage
   only on Save, put back on Cancel; Defaults is "system". The account menu's
   theme switch goes. Done: `DrawMusicWeb.ThemeChoice`, whose hook puts the
   stored theme back whenever it goes (Cancel, Back, leaving the page).
   Known gap: on the page, a change of the theme alone doesn't count as
   unsaved, so leaving by a link doesn't ask (the theme just goes back).
3. **The session layout:** the palette's Page / Strip buttons switch the
   editor's layout for the session only (an editor assign, starting from the
   preference), no longer saving the preference. Done: the assign is
   `DrawMusicWeb.Editor.View` (PR 4 adds the paper to it). A layout
   preference changed in the panel (previewed, saved or put back) is
   followed; opening and closing the panel without changing it keeps the
   session's layout.
4. **8.3, the score paper:** black on white / colour on black, a preference
   independent of the UI theme, in the form (the ink picker belongs to colour on
   black), and a session toggle in the editor. The CSS keys the score's colours
   off the paper, never `data-theme`.
   - **The toggle** (requested 2026-11-15): a **Sheet** button beneath the Save
     button, showing the paper it gives, the way the Insert / Overlay button
     shows its mode: "Sheet" in black on a white background, or in the ink on
     black. One click switches the score for the session. The ink is set only
     in Preferences (white by default).

## Tests
- Changing a field previews (the editor's layout or aids change) and stores
  nothing; Save stores; Cancel restores the stored values; Defaults fills in
  defaults and stores nothing until Save.
- A too-dark ink shows its error, isn't previewed, and can't be saved.
- The panel has no X, and Esc or a click outside leaves it open.
- The page: Save stores and leaves, Cancel discards and leaves (to
  `return_to`), and leaving another way with unsaved changes is guarded.
- (PR 3) Page / Strip in the palette changes the editor's layout and not the
  stored preference; a new editor starts from the preference.
- (PR 4) The paper toggle changes the score's colours only; the preference
  sets the start; the SVG export is black on white either way.

## Decided (2026-11-15)
1. The palette's Page / Strip, and the new paper toggle, are view-only for the
   session; the preferences set where an editor starts. The UI theme changes
   only in Preferences.
2. On the page, Save and Cancel both leave it: Save keeps, Cancel discards.
