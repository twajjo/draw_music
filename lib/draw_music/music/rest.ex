defmodule DrawMusic.Music.Rest do
  @moduledoc """
  A rest in a measure, in one voice of a staff. `offset` is ticks from the
  start of its measure.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias DrawMusic.Music.Duration

  @primary_key {:id, :binary_id, autogenerate: true}
  embedded_schema do
    field :staff, Ecto.Enum, values: [:treble, :bass]
    field :voice, :integer, default: 1
    field :offset, :integer
    field :value, Ecto.Enum, values: Duration.values()
    field :dots, :integer, default: 0
  end

  def changeset(rest, attrs) do
    rest
    |> cast(attrs, [:id, :staff, :voice, :offset, :value, :dots])
    |> validate_required([:staff, :voice, :offset, :value, :dots])
    |> validate_inclusion(:voice, 1..4)
    |> validate_number(:offset, greater_than_or_equal_to: 0)
    |> validate_inclusion(:dots, 0..2)
  end

  @doc "Length in ticks."
  def ticks(%__MODULE__{value: value, dots: dots}), do: Duration.ticks(value, dots)
end
