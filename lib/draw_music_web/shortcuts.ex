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
      mouse: "click staff",
      modes: @edit,
      action: "Place the picked note or rest; it snaps to the nearest line or space",
      diagram: :ghost_snap
    },
    %Shortcut{
      group: "Placing",
      mouse: "shift-click",
      modes: @edit,
      action: "Place it sharp (hold Shift while placing or picking up)",
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
      mouse: "double-click palette item",
      modes: @edit,
      action: "Keep it picked for several placements"
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
      mouse: "click note",
      modes: @edit,
      action: "Pick a note up; it follows the pointer by scale steps; click again to drop it"
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
        "Pick a chord; the cursor shows, sounds and names it as you move; click where its root goes"
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
      action: "Delete the selection; later music closes the gap"
    },
    %Shortcut{group: "Editing", keys: ["Ctrl+C"], modes: @edit, action: "Copy the selection"},
    %Shortcut{group: "Editing", keys: ["Ctrl+X"], modes: @edit, action: "Cut the selection"},
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
      action: "Insert mode: placing pushes later music on that staff right",
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
      mouse: "Use for this version",
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
        "Switch between Edit and Play: each has its own palette, in Play mode nothing can change the score, and a selected range narrows to its first note"
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
