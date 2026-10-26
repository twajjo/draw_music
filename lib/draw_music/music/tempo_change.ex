defmodule DrawMusic.Music.TempoChange do
  @moduledoc """
  A change of tempo inside a score (the version's `tempo_bpm` is the tempo
  at the start). `tick` is ticks from the start of the score, so the change
  stays with the music when the bars are re-drawn.

  A steady change (a ♩ = N mark) has only `bpm`: from `tick` on, the music
  goes at that speed. A gradual one (rit. or accel.) also has `to_tick` and
  `to_bpm`: the speed moves evenly from `bpm` at `tick` to `to_bpm` at
  `to_tick`, and stays there.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias DrawMusic.Music.Context

  @primary_key {:id, :binary_id, autogenerate: true}
  embedded_schema do
    field :tick, :integer
    field :bpm, :integer
    field :to_tick, :integer
    field :to_bpm, :integer
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          tick: non_neg_integer(),
          bpm: pos_integer(),
          to_tick: pos_integer() | nil,
          to_bpm: pos_integer() | nil
        }

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(change, attrs) do
    range = Context.tempo_range()

    change
    |> cast(attrs, [:id, :tick, :bpm, :to_tick, :to_bpm])
    |> validate_required([:tick, :bpm])
    |> validate_number(:tick, greater_than_or_equal_to: 0)
    |> validate_number(:bpm,
      greater_than_or_equal_to: range.first,
      less_than_or_equal_to: range.last
    )
    |> validate_number(:to_bpm,
      greater_than_or_equal_to: range.first,
      less_than_or_equal_to: range.last
    )
    |> validate_gradual()
  end

  # A gradual change has both ends, and ends after it starts.
  defp validate_gradual(changeset) do
    case {get_field(changeset, :tick), get_field(changeset, :to_tick),
          get_field(changeset, :to_bpm)} do
      {_tick, nil, nil} -> changeset
      {tick, to_tick, to_bpm} when is_integer(to_bpm) and to_tick > tick -> changeset
      _partial -> add_error(changeset, :to_tick, "must come after the start, with an end tempo")
    end
  end

  @doc "Whether the change is gradual (rit. or accel.)."
  @spec gradual?(t()) :: boolean()
  def gradual?(%__MODULE__{to_tick: nil}), do: false
  def gradual?(%__MODULE__{}), do: true

  @doc "The tempo the change leaves the music at."
  @spec end_bpm(t()) :: pos_integer()
  def end_bpm(%__MODULE__{to_bpm: nil, bpm: bpm}), do: bpm
  def end_bpm(%__MODULE__{to_bpm: to_bpm}), do: to_bpm
end
