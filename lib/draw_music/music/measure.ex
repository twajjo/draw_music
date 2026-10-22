defmodule DrawMusic.Music.Measure do
  @moduledoc """
  One bar of the grand staff: the notes and rests of both staves.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias DrawMusic.Music.{Note, Rest}

  @primary_key {:id, :binary_id, autogenerate: true}
  embedded_schema do
    embeds_many :notes, Note, on_replace: :delete
    embeds_many :rests, Rest, on_replace: :delete
  end

  @type t :: %__MODULE__{id: Ecto.UUID.t() | nil, notes: [Note.t()], rests: [Rest.t()]}

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(measure, attrs) do
    measure
    |> cast(attrs, [:id])
    |> cast_embed(:notes)
    |> cast_embed(:rests)
  end

  @doc "An empty measure with a fresh id."
  @spec new() :: t()
  def new, do: %__MODULE__{id: Ecto.UUID.generate(), notes: [], rests: []}
end
