# Finish and commit Composition details (Phase 7, item 1)

## Context
The Composition details dialog is built but uncommitted. It lives in the jj working-copy change `yvmorqox`, which sits on top of the empty, undescribed `Phase-7` change `qoulkysk`. The `/help` entry is already in `lib/draw_music_web/shortcuts.ex`, under "Saving" as "Details button". What's left is to verify it and record it as the start of the Phase-7 change. Large scores and deployment come later in the same phase.

## Steps
1. **Verify.** Run `mix precommit` through mise, and fix any warnings, format or Credo issues, or test failures in the changed files. The new `test/draw_music_web/live/composition_details_test.exs` needs to pass, and so do the existing library and editor tests.
2. **Review the test.** Check that it follows the functionality-only rule: it tests validations and our logic, not Ecto round-trips. Check that it uses the element IDs from the dialog markup.
3. **Plan doc.** The Phase 7 entry in `plans/draw-music-plan.md` already marks details as built, so no change is needed there.
4. **Record in jj.** Do not use git commits.
   - `jj squash` moves the working copy into `qoulkysk`, the change the `Phase-7` bookmark points to.
   - `jj describe -r Phase-7 -m "Composition details: name, subtitle, credits and notes from the Compositions page and the editor"`. Per memory, there is no Co-Authored-By trailer.
   - `mise.lock` is untracked, and jj will snapshot it unless it's ignored. Keep it: it pins the mise tool versions, so it should be committed.
5. **No push yet.** Phase 7 still has large scores and deployment to do. The PR against `master` waits until the phase is finished, and push or PR creation gets confirmed first.

## Verification
- `mix precommit` passes cleanly.
- `jj log` shows `Phase-7` with the description and the files, and the new working copy is empty.
- Manual browser check (the user runs the server): open Details from the Compositions page and from the editor title, edit the fields, and confirm they save at once. On a draft, confirm the fields carry into the first save. Confirm Save as new composition shows all the fields.
