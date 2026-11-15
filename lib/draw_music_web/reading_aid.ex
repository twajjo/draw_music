defmodule DrawMusicWeb.ReadingAid do
  @moduledoc """
  A reading aid's label drawn on the editor's score: a tiny letter at `x`,
  `y` (staff spaces, in its system's coordinates). `kind` says what it names:
  a staff `:line` or `:space`, `:middle_c`, or a `:note` beside its head.

  A note's name carries its note's id as `note_id`; `shown` says when it is
  drawn: `:always`, or `:when_selected` (only while its note is selected).

  Only the editor draws these (see `DrawMusicWeb.ReadingAids`); they are never
  part of the engraving, so exported sheet music never has them.
  """

  @enforce_keys [:x, :y, :text, :kind]
  defstruct [:x, :y, :text, :kind, :note_id, shown: :always]

  @type t :: %__MODULE__{
          x: float(),
          y: float(),
          text: String.t(),
          kind: :line | :space | :middle_c | :note,
          note_id: Ecto.UUID.t() | nil,
          shown: :always | :when_selected
        }
end
