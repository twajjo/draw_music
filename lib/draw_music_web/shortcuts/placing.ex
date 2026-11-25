defmodule DrawMusicWeb.Shortcuts.Placing do
  @moduledoc "The cheat-sheet's Placing and Selecting and moving entries. See `DrawMusicWeb.Shortcuts`."

  alias DrawMusicWeb.Shortcut

  @edit [:edit]

  @doc "The entries, in cheat-sheet order."
  @spec entries() :: [Shortcut.t()]
  def entries do
    [
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
        keys: ["B"],
        modes: @edit,
        action:
          "Pick one beat of the meter, as a note or a rest: a quarter in 4/4, a dotted quarter in 6/8, 9/8 and 12/8. The palette shows it as “Beat” and its note, beside the lengths"
      },
      %Shortcut{
        group: "Placing",
        keys: ["."],
        modes: @edit,
        action:
          "Dot the picked value, or the selected notes (a 128th takes one dot, a 256th none)"
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
          "Insert: every note and rest has a gap before it; the picked item goes in front of it and everything after moves right; the preview waits in the gap"
      },
      %Shortcut{
        group: "Placing",
        mouse: "hover a bar, then click a zone",
        modes: @edit,
        action:
          "Overlay: the bar under the pointer is shaded in zones, one per place the picked item can start: its own length if it divides the beat (an eighth: 8 in 4/4, 12 in 12/8), else one per beat (a half in 4/4: 4, so it can start on beat 2). The zone under the pointer lights up over all the time the item will cover; a click types over exactly that, and a note running past the bar line is tied into the next bar",
        diagram: :overlay_zones
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
        mouse: "click empty music",
        modes: @edit,
        action:
          "Put the cursor there: a thin line in the selection colour, where the next paste goes. It blinks in Overlay mode, where a paste or a placed note replaces what follows it. Placing a note, rest or chord, or selecting one note or rest, puts it just after it"
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
          "Move the selection a scale step; each note keeps its sharp or flat. A note taken past its staff's half of the gap (treble below D3, bass above B4) moves to the other staff, joining a note of the same length there as a chord. With nothing selected (Page layout): move the cursor to the line of music above or below, about the same place across"
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
        action:
          "Move the selection whole, past the note or rest beside it: it is never split or tied by the move, and the music it passes moves back to fill its place. Near a bar line it jumps the bar line whole; a rest lands only where the rules for rests allow (in 4/4 a half rest on beat 1 or 3), passing more music if it must. It stays selected. With nothing selected: move the cursor back or on to where the previous or next note or rest starts, on either staff (Esc clears the selection)"
      },
      %Shortcut{
        group: "Selecting and moving",
        keys: ["Ctrl+ArrowLeft", "Ctrl+ArrowRight"],
        modes: @edit,
        action:
          "With nothing selected: move the cursor back or on a bar (with a selection, nothing)"
      }
    ]
  end
end
