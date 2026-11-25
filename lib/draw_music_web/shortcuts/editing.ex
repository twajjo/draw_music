defmodule DrawMusicWeb.Shortcuts.Editing do
  @moduledoc "The cheat-sheet's Ties and chords, Measures and Editing entries. See `DrawMusicWeb.Shortcuts`."

  alias DrawMusicWeb.Shortcut

  @edit [:edit]

  @doc "The entries, in cheat-sheet order."
  @spec entries() :: [Shortcut.t()]
  def entries do
    [
      # Ties and chords
      %Shortcut{group: "Ties and chords", keys: ["T"], modes: @edit, action: "Pick the tie tool"},
      %Shortcut{
        group: "Ties and chords",
        mouse: "drag note to note",
        modes: @edit,
        action: "With the tie tool, tie two touching notes of the same pitch",
        diagram: :tie_drag
      },
      %Shortcut{
        group: "Ties and chords",
        mouse: "Chords menu",
        modes: @edit,
        action:
          "Chord mode: pick a chord before or after the length; the ghost shows, sounds and names it (Dmaj, F♯min) as you drag; let go where its root goes. Pick it again, or Single notes, to go back to notes"
      },
      %Shortcut{
        group: "Ties and chords",
        mouse: "right-click note, Add a 3rd",
        modes: @edit,
        action:
          "Add a note a third above the chord's top note, or below its bottom one, on the key's version of that letter"
      },
      %Shortcut{
        group: "Ties and chords",
        mouse: "Chords menu, notes selected",
        modes: @edit,
        action:
          "With nothing picked (Esc), turn the selected notes into the chord, each built on its lowest note"
      },
      # Measures
      %Shortcut{
        group: "Measures",
        mouse: "hover a bar",
        modes: @edit,
        action: "⊕ adds a bar before it; ⊖ deletes it"
      },
      %Shortcut{
        group: "Measures",
        mouse: "Add bar",
        modes: @edit,
        action: "Add a bar at the end"
      },
      # Editing
      %Shortcut{
        group: "Editing",
        keys: ["Delete", "Backspace"],
        modes: @edit,
        action:
          "Delete the selection. Overlay: nothing else moves, and the gap shows as rests. Insert: later music on that staff moves left to close it"
      },
      %Shortcut{
        group: "Editing",
        keys: ["Ctrl+A"],
        modes: @edit,
        action:
          "Select every note and rest, on both staves (also the palette's Select all button), so copy, cut, delete, transpose and moves apply to the whole piece"
      },
      %Shortcut{group: "Editing", keys: ["Ctrl+C"], modes: @edit, action: "Copy the selection"},
      %Shortcut{
        group: "Editing",
        keys: ["Ctrl+X"],
        modes: @edit,
        action: "Cut the selection (it leaves a gap or closes it, as Delete does)"
      },
      %Shortcut{
        group: "Editing",
        keys: ["Ctrl+V"],
        modes: @edit,
        action:
          "Paste where the selection starts, or at the cursor (the thin blue line) with nothing selected; the cursor then moves just after the pasted music. Insert: it goes ahead, and the selection and later music move right. Overlay: it replaces the selection (or, with nothing selected, as much music as it lasts), and nothing moves"
      },
      %Shortcut{
        group: "Editing",
        keys: ["Ctrl+Home"],
        modes: @edit,
        action: "Put the cursor at the start of the piece, and scroll to it"
      },
      %Shortcut{
        group: "Editing",
        keys: ["Ctrl+End"],
        modes: @edit,
        action: "Put the cursor at the end of the piece, and scroll to it, to add music after it"
      },
      %Shortcut{group: "Editing", keys: ["Ctrl+Z"], modes: @edit, action: "Undo"},
      %Shortcut{group: "Editing", keys: ["Ctrl+Shift+Z", "Ctrl+Y"], modes: @edit, action: "Redo"},
      %Shortcut{
        group: "Editing",
        keys: ["Insert"],
        modes: @edit,
        action:
          "Switch between Insert (the default) and Overlay, like typing in a text editor (also the palette's Overlay/Insert button). Insert: the new item goes in front of the note or rest you click before (rests are items like notes, the ones after the music too), everything after it on that staff moves right (the rests at the very end shrink, like trailing spaces, and a bar is added if notes are pushed past the last one), and deleting pulls later music left. In Insert the space after a bar's last note or rest belongs to the next bar: a click there starts the next bar (a bar is added after the last one), leaving the bar you clicked in as it is. Overlay: the new item replaces the time it covers on that staff, from the zone you click (see the shaded zones): a half replaces two beats of notes and rests, a note sounding into it is shortened, and what's left of a covered note becomes rests. Either way a note too long for the bar is tied over the bar line",
        diagram: :insert_shift
      },
      %Shortcut{
        group: "Editing",
        mouse: "Suggest key (palette)",
        modes: @edit,
        action:
          "When the notes carry clearly more accidentals than another key would write (the whole piece is judged), as when music entered by ear in C major is really in E♭, Suggest key lists better keys, the one leaving the fewest accidentals first, each with how many it would leave and on which notes (only keys whose accidentals fall on at most two different notes are listed). Pick one: the key signature changes and every note is re-spelled (A♯ becomes B♭), but nothing sounds different. Undo puts it back; a saved piece is saved in the new key"
      },
      %Shortcut{
        group: "Editing",
        mouse: "right-click",
        modes: @edit,
        action:
          "The menu for what's selected, wherever you right-click in the music. One note or rest: its own menu (split, length, rest or note, ties, a tempo change here, copy, cut, paste here, delete); one tempo mark: its dialog. Two or more: the selection's menu (transpose, reverse, copy, cut, paste here, delete). Paste here puts what you copied in where the note or rest (or the selection) starts, as Ctrl+V does: ahead of it in Insert, replacing it in Overlay. With nothing selected, right-click a note or rest for its menu"
      },
      %Shortcut{
        group: "Editing",
        mouse: "right-click → Tempo change here…",
        modes: @edit,
        action:
          "Change the tempo where that note or rest starts: a ♩ = N mark, or tick Gradually for a rit. or accel. that reaches another tempo over some beats. The tempo in the score settings is the one the piece starts at, so a change can't go on its first beat",
        diagram: :tempo_mark
      },
      %Shortcut{
        group: "Editing",
        mouse: "click / double-click a tempo mark",
        modes: @edit,
        action:
          "Click selects it (Delete removes it; Select all takes it in); double-click or right-click opens it to change or delete"
      },
      %Shortcut{
        group: "Editing",
        mouse: "drag a tempo mark",
        modes: @edit,
        action:
          "Move it along the music (it snaps to notes and rests); drag a rit.'s or accel.'s end tempo to make it longer or shorter",
        diagram: :tempo_ramp
      },
      %Shortcut{
        group: "Editing",
        mouse: "double-click / right-click the opening tempo",
        modes: @edit,
        action:
          "The marking over the first bar (e.g. Moderato ♩ = 100) is the score's settings: it opens them, to choose another marking or starting tempo"
      }
    ]
  end
end
