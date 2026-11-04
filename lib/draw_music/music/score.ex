defmodule DrawMusic.Music.Score do
  @moduledoc """
  The music of a version: its measures, in order, and the tempo changes
  inside it (ordered by tick). Key, time signature, pickup and the starting
  tempo live on the version (see `DrawMusic.Music.Context`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias DrawMusic.Music.{Measure, TempoChange}

  @primary_key false
  embedded_schema do
    embeds_many :measures, Measure, on_replace: :delete
    embeds_many :tempos, TempoChange, on_replace: :delete
  end

  @type t :: %__MODULE__{measures: [Measure.t()], tempos: [TempoChange.t()]}

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(score, attrs) do
    score
    |> cast(attrs, [])
    |> cast_embed(:measures)
    |> cast_embed(:tempos)
  end

  @doc "A score of `count` empty measures."
  @spec new() :: t()
  @spec new(pos_integer()) :: t()
  def new(count \\ 1) when count >= 1 do
    %__MODULE__{measures: for(_ <- 1..count, do: Measure.new())}
  end
end
