defmodule DrawMusicWeb.Help.Shortcuts do
  @moduledoc """
  The cheat-sheet's contents: every key and mouse action the editor
  understands, for `/help` and the editor's help dialog. The entries are
  kept by area in `Shortcuts.Placing`, `Shortcuts.Editing` and
  `Shortcuts.SavingAndPlayback`.

  Keys use the names in `assets/js/score_editor/keys.json`, the list the
  editor's hook acts on; a test keeps the two in step.
  """

  alias DrawMusicWeb.Help.Shortcut
  alias DrawMusicWeb.Help.Shortcuts.{Editing, Placing, SavingAndPlayback}

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

  @shortcuts Placing.entries() ++ Editing.entries() ++ SavingAndPlayback.entries()

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
