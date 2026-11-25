defmodule DrawMusicWeb.Help.Shortcuts.SavingAndPlayback do
  @moduledoc "The cheat-sheet's Saving, Playback and Modes entries. See `DrawMusicWeb.Help.Shortcuts`."

  alias DrawMusicWeb.Help.Shortcut

  @play [:play]
  @both [:edit, :play]

  @doc "The entries, in cheat-sheet order."
  @spec entries() :: [Shortcut.t()]
  def entries do
    [
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
        mouse: "Import .mid, in the top bar",
        modes: @both,
        action:
          "Over the page you're on (Cancel leaves you there, unsaved work kept), read a .mid file into the library under the name it carries (you can change it). If the name is taken: replace that key's versions with it, add it as a new version, or pick another name"
      },
      %Shortcut{
        group: "Saving",
        mouse: "account menu › Preferences",
        modes: @both,
        action:
          "Your own preferences (light, dark or system theme; the layout and paper each score starts with, the ink on black, reading aids). Changes show at once but aren't kept until Save; Cancel puts back what you had, and Defaults fills in the starting values (Save to keep them). Only Save or Cancel closes it"
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
      %Shortcut{
        group: "Modes",
        mouse: "Sheet, under Save",
        modes: @both,
        action:
          "Switch the score between black on white and your ink on black (the button shows which), for now only: each score opens on the paper set in Preferences, where the ink is chosen too. Downloads are always black on white"
      },
      %Shortcut{
        group: "Modes",
        keys: ["Escape"],
        modes: @both,
        action:
          "Close an open drop-down menu (Save's arrow, Chords, Suggest key, the versions) and do nothing else; a click anywhere outside it, or picking an item, closes it too"
      },
      %Shortcut{group: "Modes", keys: ["?"], modes: @both, action: "Show this cheat-sheet"}
    ]
  end
end
