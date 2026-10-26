defmodule DrawMusicWeb.TempoDialog do
  @moduledoc """
  The open tempo dialog: the change it edits (`id`, nil for a new one), the
  tick it starts at, and its form (see `DrawMusicWeb.TempoForm`).
  """

  @enforce_keys [:tick, :form]
  defstruct [:id, :tick, :form]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          tick: non_neg_integer(),
          form: Phoenix.HTML.Form.t()
        }
end
