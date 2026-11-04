defmodule DrawMusicWeb.ScorePiece do
  @moduledoc """
  One piece of the score as the editor draws it: its own `<svg>`, showing
  the rectangle `x0..x1` × `y0..y1` of the page (staff spaces). Page layout
  has a piece per system; Strip layout cuts its one system into runs of
  bars. The pieces tile the page, so the browser can skip drawing those out
  of view, and an edit resends only the pieces it changes.

  `groups` are the systems it draws from, each `{index, y, items}`; `whole?`
  says they're whole systems (not a run of bars). `selected` holds the ids
  of its notes, rests and tempo marks that are selected.
  """

  alias DrawMusic.Engraving.Item

  @enforce_keys [:id, :x0, :x1, :y0, :y1, :groups, :whole?]
  defstruct [:id, :x0, :x1, :y0, :y1, :groups, :whole?, selected: MapSet.new()]

  @type t :: %__MODULE__{
          id: String.t(),
          x0: float(),
          x1: float(),
          y0: float(),
          y1: float(),
          groups: [{non_neg_integer(), float(), [Item.t()]}],
          whole?: boolean(),
          selected: MapSet.t(String.t())
        }
end
