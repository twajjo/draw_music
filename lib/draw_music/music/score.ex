defmodule DrawMusic.Music.Score do
  @moduledoc """
  The music of a version: its measures, in order. Key, time signature,
  pickup and tempo live on the version (see `DrawMusic.Music.Context`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias DrawMusic.Music.Measure

  @primary_key false
  embedded_schema do
    embeds_many :measures, Measure, on_replace: :delete
  end

  def changeset(score, attrs) do
    score
    |> cast(attrs, [])
    |> cast_embed(:measures)
  end

  @doc "A score of `count` empty measures."
  def new(count \\ 1) when count >= 1,
    do: %__MODULE__{measures: for(_ <- 1..count, do: Measure.new())}
end
