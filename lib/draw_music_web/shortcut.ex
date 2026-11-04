defmodule DrawMusicWeb.Shortcut do
  @moduledoc """
  One line of the cheat-sheet: the keys (as `assets/js/score_editor/keys.json`
  names them) or mouse gesture that does something, the modes it works
  in, what it does, and the diagram that shows it, if any.
  """

  @enforce_keys [:group, :modes, :action]
  defstruct [:group, :modes, :action, :mouse, :diagram, keys: []]

  @type mode :: :edit | :play
  @type t :: %__MODULE__{
          group: String.t(),
          keys: [String.t()],
          mouse: String.t() | nil,
          modes: [mode()],
          action: String.t(),
          diagram: atom() | nil
        }
end
