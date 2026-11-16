defmodule DrawMusicWeb.Shortcuts do
  @moduledoc """
  The cheat-sheet's contents: every key and mouse action the editor
  understands, for `/help` and the editor's help dialog. Keys use the names
  in `assets/js/score_editor/keys.json`, the list the editor's hook acts on;
  a test keeps the two in step.
  """

  alias DrawMusicWeb.Shortcut

  @groups [
    "Placing",
    "Selecting and moving",
    "Ties and chords",
    "Measures",
    "Editing",
    "Saving",
    "Playback",
    "Modes"
  ]
  @play_first ["Playback", "Modes"]

  @edit [:edit]
  @play [:play]
  @both [:edit, :play]

  @shortcuts [
    # Placing
    %Shortcut{
      group: "Placing",
      keys: ~w(1 2 3 4 5 6 7 8 9),
      modes: @edit,
      action: "Pick a whole note (1) down to a 256th (9) to place"
    },
    %Shortcut{
      group: "Placing",
      keys: ["0"],
      modes: @edit,
      action: "Put the picked note, rest, chord or tie tool down (nothing picked)"
    },
    %Shortcut{
      group: "Placing",
      keys: ["R"],
      modes: @edit,
      action: "Switch the palette between notes and rests"
    },
    %Shortcut{
      group: "Placing",
      keys: ["."],
      modes: @edit,
      action: "Dot the picked value, or the selected notes (a 128th takes one dot, a 256th none)"
    },
    %Shortcut{
      group: "Placing",
      mouse: "press, drag, let go",
      modes: @edit,
      action:
        "Press on the staff to hear the picked note, drag up or down to hear each line and space, and let go to place it",
      diagram: :ghost_snap
    },
    %Shortcut{
      group: "Placing",
      mouse: "hover, drag or select a note",
      modes: @edit,
      action:
        "Its name shows beside it, like G♯, or F♮ where a natural sign is needed, while you place it, drag it, or have it selected (a range of notes too, and as ↑/↓ moves them). Turn this off in Preferences › Reading aids › Show note names, or turn off \"Only while editing and placing\" there to name every note at all times; never in downloads"
    },
    %Shortcut{
      group: "Placing",
      mouse: "the letters left of the staves",
      modes: @edit,
      action:
        "Name each staff's lines (treble E G B D F, bass G B D F A) and spaces (F A C E, A C E G), and middle C, at the start of each line of music. Turn them on in Preferences › Reading aids; they never appear in downloads"
    },
    %Shortcut{
      group: "Placing",
      mouse: "click in the gap before a note or rest",
      modes: @edit,
      action:
        "Every note and rest has a gap before it. Insert: the picked item goes in front of it and everything after moves right; the preview waits in the gap. Overlay: the item starts there and types over the time it covers"
    },
    %Shortcut{
      group: "Placing",
      mouse: "shift-click",
      modes: @edit,
      action: "Place it sharp (hold Shift while placing or dragging)",
      diagram: :accidental_modifiers
    },
    %Shortcut{
      group: "Placing",
      mouse: "ctrl-click",
      modes: @edit,
      action: "Place it flat (Ctrl or Alt)"
    },
    %Shortcut{
      group: "Placing",
      keys: ["Escape"],
      modes: @edit,
      action: "Stop placing, or clear the selection"
    },
    # Selecting and moving
    %Shortcut{
      group: "Selecting and moving",
      mouse: "click note or rest",
      modes: @edit,
      action:
        "Select it, even with something picked (every rest on the page can be selected); Delete, the arrows, the menu and the palette's dot and accidentals act on it"
    },
    %Shortcut{
      group: "Selecting and moving",
      mouse: "drag note",
      modes: @edit,
      action:
        "Move it up or down, hearing each step; it lands when you let go, keeping its sharp or flat (hold Shift for a sharp, Ctrl or Alt for a flat). Alone it can move to the other staff; a selected note brings the selection. A note stays on its staff up to its fourth ledger line into the gap (treble down to D3, bass up to B4); past that it goes to the other staff. Right-click › Put on the treble/bass staff moves notes on purpose"
    },
    %Shortcut{
      group: "Selecting and moving",
      mouse: "shift-click note",
      modes: @edit,
      action: "Add a note or rest to the selection, or take it out"
    },
    %Shortcut{
      group: "Selecting and moving",
      mouse: "drag empty area",
      modes: @edit,
      action:
        "Select everything in a span of time, on both staves, like selecting text: from where you press to where you let go, forwards or backwards and across lines. What it will select lights up as you drag",
      diagram: :rubber_band
    },
    %Shortcut{
      group: "Selecting and moving",
      keys: ["ArrowUp", "ArrowDown"],
      modes: @edit,
      action:
        "Move the selection a scale step; each note keeps its sharp or flat. A note taken past its staff's half of the gap (treble below D3, bass above B4) moves to the other staff, joining a note of the same length there as a chord"
    },
    %Shortcut{
      group: "Selecting and moving",
      keys: ["Shift+ArrowUp", "Shift+ArrowDown"],
      modes: @edit,
      action: "Move it an octave"
    },
    %Shortcut{
      group: "Selecting and moving",
      keys: ["Ctrl+ArrowUp", "Ctrl+ArrowDown"],
      modes: @edit,
      action: "Move it a semitone"
    },
    %Shortcut{
      group: "Selecting and moving",
      keys: ["ArrowLeft", "ArrowRight"],
      modes: @edit,
      action: "Move it a beat earlier or later"
    },
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
    %Shortcut{group: "Measures", mouse: "Add bar", modes: @edit, action: "Add a bar at the end"},
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
      action: "Paste where you last clicked; later music moves right"
    },
    %Shortcut{group: "Editing", keys: ["Ctrl+Z"], modes: @edit, action: "Undo"},
    %Shortcut{group: "Editing", keys: ["Ctrl+Shift+Z", "Ctrl+Y"], modes: @edit, action: "Redo"},
    %Shortcut{
      group: "Editing",
      keys: ["Insert"],
      modes: @edit,
      action:
        "Switch between Insert (the default) and Overlay, like typing in a text editor (also the palette's Overlay/Insert button). Insert: the new item goes in front of the note or rest you click before (rests are items like notes, the ones after the music too), everything after it on that staff moves right (the rests at the very end shrink, like trailing spaces, and a bar is added if notes are pushed past the last one), and deleting pulls later music left. Overlay: the new item replaces the time it covers on that staff, from the beat you click: a half replaces two beats of notes and rests, a note sounding into it is shortened, and what's left of a covered note becomes rests. Either way a note too long for the bar is tied over the bar line, and the space after a bar's last note or rest belongs to the next bar: a click there starts the next bar (a bar is added after the last one), leaving the bar you clicked in as it is",
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
        "The menu for what's selected, wherever you right-click in the music. One note or rest: its own menu (split, length, rest or note, ties, a tempo change here, delete); one tempo mark: its dialog. Two or more: the selection's menu (transpose, reverse, copy, cut, delete). With nothing selected, right-click a note or rest for its menu"
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
    },
    # Saving
    %Shortcut{
      group: "Saving",
      mouse: "Save menu",
      modes: @both,
      action: "Save, save as a new version, or save as a new composition"
    },
    %Shortcut{
      group: "Saving",
      mouse: "Details button",
      modes: @both,
      action:
        "Change the composition's name, subtitle, credits and notes (beside its title here, or on the Compositions page). They're shared by every key and version and saved at once; an unsaved score keeps them for its first save"
    },
    %Shortcut{
      group: "Saving",
      mouse: "Import .mid",
      modes: @both,
      action:
        "On the Compositions page, read a .mid file into the library under the name it carries (you can change it). If the name is taken: replace that key's versions with it, add it as a new version, or pick another name"
    },
    %Shortcut{
      group: "Saving",
      mouse: "account menu › Preferences",
      modes: @both,
      action:
        "Your own preferences (light, dark or system theme; layout, dark-mode ink, reading aids). Changes show at once but aren't kept until Save; Cancel puts back what you had, and Defaults fills in the starting values (Save to keep them). Only Save or Cancel closes it"
    },
    # Playback (the play controls replace the edit palette in Play mode)
    %Shortcut{
      group: "Playback",
      keys: ["Space"],
      modes: @play,
      action:
        "Play the selection, from the selected note, or from the start; again to pause or resume"
    },
    %Shortcut{
      group: "Playback",
      keys: ["Home"],
      mouse: "⏮ (bar and arrow) button",
      modes: @play,
      action:
        "Back to the start of what's being played (the chosen measures, the selection, or the whole piece); playing, it carries on from there"
    },
    %Shortcut{
      group: "Playback",
      keys: ["End"],
      mouse: "⏭ (arrow and bar) button",
      modes: @play,
      action:
        "To the end of what's being played: the playhead waits there, so ⏪ or ⏪⏪ can go back a measure or line from the end. Playing with Loop on, back to its start instead. At the end, Play says there's nothing to play, or with Loop on starts again from the start"
    },
    %Shortcut{
      group: "Playback",
      mouse: "Measures [from] to [to]",
      modes: @play,
      action:
        "Play just these measures (both included; one measure when they're the same): they're selected, and Play, Loop, the skips and ⏭ stay inside them. Changed only while not playing; press Play to play them"
    },
    %Shortcut{
      group: "Playback",
      mouse: "Whole piece button",
      modes: @play,
      action: "Play the whole piece again, measures 1 to the end (clears the selection)"
    },
    %Shortcut{
      group: "Playback",
      mouse: "⏪ button",
      modes: @play,
      action:
        "Back to the start of this measure, or of the one before if it has only just begun; before playing, Play will start there"
    },
    %Shortcut{
      group: "Playback",
      mouse: "⏪⏪ (three arrows) button",
      modes: @play,
      action:
        "Back to the start of this line of music, or of the one before if it has only just begun (Page layout; off in Strip, a single line)"
    },
    %Shortcut{
      group: "Playback",
      keys: ["L"],
      modes: @play,
      action: "Repeat the selection, or the whole piece",
      diagram: :loop
    },
    %Shortcut{
      group: "Playback",
      keys: ["Escape"],
      modes: @play,
      action: "Stop, back to the start of what's being played (also the ⏹ button)"
    },
    %Shortcut{
      group: "Playback",
      mouse: "⏩ button",
      modes: @play,
      action:
        "Skip to the start of the next measure: playing, it carries on from there; paused, it waits there; before playing, Play will start there"
    },
    %Shortcut{
      group: "Playback",
      mouse: "⏩⏩ (three arrows) button",
      modes: @play,
      action:
        "Skip to the start of the next line of music (Page layout; off in Strip, a single line)"
    },
    %Shortcut{
      group: "Playback",
      mouse: "Play mode",
      modes: @play,
      action:
        "A red line marks the point being played, and the score follows it: in Strip layout it turns sideways when the line nears the right edge, in Page layout it scrolls down to each new line of music. Before you play, it waits where Play will start (where the skips or ⏭ moved it, else the start of the chosen measures, the selection, or the piece) and the score scrolls to it. Pausing leaves the line where it is; Rewind takes it back to the start",
      diagram: :playhead
    },
    %Shortcut{
      group: "Playback",
      mouse: "Hear as",
      modes: @play,
      action: "Pick the instrument to listen with; the version keeps its own"
    },
    %Shortcut{
      group: "Playback",
      mouse: "Set as version Instrument",
      modes: @play,
      action: "Make the version's instrument the one you're hearing (after you confirm)"
    },
    %Shortcut{
      group: "Playback",
      mouse: "click note (Play mode)",
      modes: @play,
      action: "Hear the note and its chord, and start there",
      diagram: :play_cursor
    },
    %Shortcut{
      group: "Playback",
      mouse: "drag (Play mode)",
      modes: @play,
      action: "Select a span to play, from where you press to where you let go, across lines",
      diagram: :range_playback
    },
    # Modes
    %Shortcut{
      group: "Modes",
      keys: ["P"],
      modes: @both,
      action:
        "Switch between Edit and Play: each has its own palette, in Play mode nothing can change the score, and going back to Edit narrows a selected range to its first note"
    },
    %Shortcut{
      group: "Modes",
      mouse: "Page / Strip, under Edit and Play",
      modes: @both,
      action:
        "Show the score in rows like sheet music (Page) or as one long staff (Strip), for now only: each score opens in the layout set in Preferences"
    },
    %Shortcut{group: "Modes", keys: ["?"], modes: @both, action: "Show this cheat-sheet"}
  ]

  @doc "Every entry, grouped in cheat-sheet order."
  @spec all() :: [Shortcut.t()]
  def all, do: @shortcuts

  @doc "Every entry, with the groups that matter most in `mode` first."
  @spec for_mode(Shortcut.mode()) :: [Shortcut.t()]
  def for_mode(mode) do
    order = group_order(mode)
    Enum.sort_by(@shortcuts, &Enum.find_index(order, fn group -> group == &1.group end))
  end

  @doc "The groups, in the order the cheat-sheet lists them."
  @spec groups() :: [String.t()]
  def groups, do: @groups

  @doc "Every key named on the cheat-sheet."
  @spec handled_keys() :: [String.t()]
  def handled_keys do
    @shortcuts
    |> Enum.flat_map(& &1.keys)
    |> Enum.uniq()
  end

  defp group_order(:play), do: @play_first ++ (@groups -- @play_first)
  defp group_order(:edit), do: @groups
end
