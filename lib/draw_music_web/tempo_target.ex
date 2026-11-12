defmodule DrawMusicWeb.TempoTarget do
  @moduledoc """
  What the tempo dialog (`DrawMusicWeb.Editor.TempoDialog`) edits: the
  change (`id`, nil for a new one), the tick it starts at, and the form's
  starting `params` (see `DrawMusicWeb.TempoForm`).

  A rit. or accel. from there may reach as far as `reach` (a tick), where
  the next change starts or the score ends (`until`): `max_beats` beats of
  the time signature, as the form shows it.
  """

  @enforce_keys [:tick, :params, :reach, :until, :max_beats]
  defstruct [:id, :tick, :params, :reach, :until, :max_beats]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          tick: non_neg_integer(),
          params: %{String.t() => String.t()},
          reach: pos_integer(),
          until: :next_change | :score_end,
          max_beats: String.t()
        }
end
