defmodule DrawMusicWeb.ContextMenu do
  @moduledoc """
  An open right-click menu: the event it was opened on (`id`), the events
  its actions apply to (`ids`: the whole selection for `:selection`), where
  it sits on screen, and the staff step that was clicked (for "Make it a
  note here").
  """

  @enforce_keys [:id, :ids, :kind, :x, :y]
  defstruct [:id, :ids, :kind, :x, :y, :step]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          ids: [Ecto.UUID.t()],
          kind: :note | :rest | :selection,
          x: number(),
          y: number(),
          step: integer() | nil
        }
end
