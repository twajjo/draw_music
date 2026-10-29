defmodule DrawMusic.Music.Rest do
  @moduledoc """
  A rest in a measure, in one voice of a staff. `offset` is ticks from the
  start of its measure.

  A `filler` rest is one the editor wrote into a gap rather than one the
  user placed: it is rewritten after every edit (grouped on the beats), and
  an insert pushes into trailing filler instead of moving it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias DrawMusic.Music.{Duration, Note}

  @primary_key {:id, :binary_id, autogenerate: true}
  embedded_schema do
    field :staff, Ecto.Enum, values: [:treble, :bass]
    field :voice, :integer, default: 1
    field :offset, :integer
    field :value, Ecto.Enum, values: Duration.values()
    field :dots, :integer, default: 0
    field :filler, :boolean, default: false
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          staff: Note.staff(),
          voice: Note.voice(),
          offset: non_neg_integer(),
          value: Duration.value(),
          dots: 0..2,
          filler: boolean()
        }

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(rest, attrs) do
    rest
    |> cast(attrs, [:id, :staff, :voice, :offset, :value, :dots, :filler])
    |> validate_required([:staff, :voice, :offset, :value, :dots])
    |> validate_inclusion(:voice, Note.voices())
    |> validate_number(:offset, greater_than_or_equal_to: 0)
    |> Duration.validate_dots()
  end

  @doc "Length in ticks."
  @spec ticks(t()) :: pos_integer()
  def ticks(%__MODULE__{value: value, dots: dots}), do: Duration.ticks(value, dots)
end
