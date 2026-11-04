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
      keys: ~w(1 2 3 4 5 6 7),
      modes: @edit,
      action: "Pick a whole note (1) down to a 64th (7) to place"
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
      action: "Dot the picked value, or the selected notes"
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
        "Move it up or down, hearing each step; it lands when you let go. Alone it can move to the other staff; a selected note brings the selection"
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
      action: "Select everything in a span of time, on both staves",
      diagram: :rubber_band
    },
    %Shortcut{
      group: "Selecting and moving",
      keys: ["ArrowUp", "ArrowDown"],
      modes: @edit,
      action: "Move the selection a scale step"
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
        "Switch between Insert (the default) and Overlay, like typing in a text editor (also the palette's Overlay/Insert button). Insert: the new item goes in front of the one you click before, everything after it on that staff moves right (only the rests at the very end shrink), a click past the music lands right after it, and deleting pulls later music left. Overlay: the new item replaces the time it covers on that staff, from the beat you click: a half replaces two beats of notes and rests, a note sounding into it is shortened, and what's left of a covered note becomes rests. Either way a note too long for the bar is tied over the bar line",
      diagram: :insert_shift
    },
    %Shortcut{
      group: "Editing",
      mouse: "right-click",
      modes: @edit,
      action: "A note's menu: split, length, rest or note, tie, transpose, delete"
    },
    # Saving
    %Shortcut{
      group: "Saving",
      mouse: "Save menu",
      modes: @both,
      action: "Save, save as a new version, or save as a new composition"
    },
    # Playback (the play controls replace the edit palette in Play mode)
    %Shortcut{
      group: "Playback",
      keys: ["Space"],
      modes: @play,
      action:
        "Play the selection, from the selected note, or from the start; again to pause or resume"
    },
    %Shortcut{group: "Playback", keys: ["Home"], modes: @play, action: "Back to the start point"},
    %Shortcut{
      group: "Playback",
      keys: ["L"],
      modes: @play,
      action: "Repeat the selection, or the whole piece",
      diagram: :loop
    },
    %Shortcut{group: "Playback", keys: ["Escape"], modes: @play, action: "Stop, while playing"},
    %Shortcut{
      group: "Playback",
      mouse: "Hear as",
      modes: @play,
      action: "Pick the instrument to listen with; the version keeps its own"
    },
    %Shortcut{
      group: "Playback",
      mouse: "Set selection to version Instrument",
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
      action: "Select a span to play",
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
    %Shortcut{group: "Modes", keys: ["?"], modes: @both, action: "Show this cheat-sheet"}
  ]

  @doc "Every entry, grouped in cheat-sheet order."
  @spec all() :: [Shortcut.t()]
  def all, do: @shortcuts

  @doc "The groups, in the order the cheat-sheet lists them."
  @spec groups() :: [String.t()]
  def groups, do: @groups

  @doc "Every entry, with the groups that matter most in `mode` first."
  @spec for_mode(Shortcut.mode()) :: [Shortcut.t()]
  def for_mode(mode) do
    order = group_order(mode)
    Enum.sort_by(@shortcuts, &Enum.find_index(order, fn group -> group == &1.group end))
  end

  defp group_order(:play), do: @play_first ++ (@groups -- @play_first)
  defp group_order(:edit), do: @groups

  @doc "Every key named on the cheat-sheet."
  @spec handled_keys() :: [String.t()]
  def handled_keys do
    @shortcuts
    |> Enum.flat_map(& &1.keys)
    |> Enum.uniq()
  end
end
