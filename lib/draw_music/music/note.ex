defmodule DrawMusic.Music.Note do
  @moduledoc """
  A note in a measure. `offset` is ticks from the start of its measure;
  `step` and `alter` give the written pitch (see `DrawMusic.Music.Pitch`).

  Each staff holds up to four `voice`s: independent rhythmic lines that may
  overlap (e.g. a quarter note in voice 1 against two eighths in voice 2).
  Within one voice, notes with the same offset and length form a chord.

  `tie_to` is the id of the next note in a tie; it always points forward in
  time to a note of the same pitch that starts exactly where this one ends.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias DrawMusic.Music.{Duration, Pitch}

  @voices 1..4

  # Where an event is and how long: what `from/2` takes from its source.
  @position [:staff, :voice, :offset, :value, :dots]

  @primary_key {:id, :binary_id, autogenerate: true}
  embedded_schema do
    field :staff, Ecto.Enum, values: [:treble, :bass]
    field :voice, :integer, default: 1
    field :offset, :integer
    field :value, Ecto.Enum, values: Duration.values()
    field :dots, :integer, default: 0
    field :step, :integer
    field :alter, :integer, default: 0
    field :tie_to, :binary_id
  end

  @typedoc "A staff of the grand staff."
  @type staff :: :treble | :bass

  @typedoc "One of a staff's independent rhythmic lines; matches `voices/0`."
  @type voice :: 1..4

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          staff: staff(),
          voice: voice(),
          offset: non_neg_integer(),
          value: Duration.value(),
          dots: 0..2,
          step: integer(),
          alter: -2..2,
          tie_to: Ecto.UUID.t() | nil
        }

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(note, attrs) do
    note
    |> cast(attrs, [:id, :staff, :voice, :offset, :value, :dots, :step, :alter, :tie_to])
    |> validate_required([:staff, :voice, :offset, :value, :dots, :step, :alter])
    |> validate_inclusion(:voice, @voices)
    |> validate_number(:offset, greater_than_or_equal_to: 0)
    |> Duration.validate_dots()
    |> validate_inclusion(:alter, Pitch.alters())
    |> validate_range()
  end

  @doc """
  A note where `source` is (a placement, note or rest): its staff, voice,
  offset, value and dots, with `fields` on top (the id, step and alter at
  least).
  """
  @spec from(map(), map() | keyword()) :: t()
  def from(source, fields) do
    struct!(__MODULE__, Map.merge(Map.take(source, @position), Map.new(fields)))
  end

  @doc "Sounding pitch as a MIDI number."
  @spec midi(t()) :: integer()
  def midi(%__MODULE__{step: step, alter: alter}), do: Pitch.midi(step, alter)

  @doc "Length in ticks."
  @spec ticks(t()) :: pos_integer()
  def ticks(%__MODULE__{value: value, dots: dots}), do: Duration.ticks(value, dots)

  @doc "The voices a staff holds (shared by rests)."
  @spec voices() :: Range.t()
  def voices, do: @voices

  defp range_error(changeset, step, alter) when is_integer(step) and is_integer(alter) do
    if Pitch.in_range?(Pitch.midi(step, alter)) do
      changeset
    else
      add_error(changeset, :step, "is outside the piano's range (A0–C8)")
    end
  end

  defp range_error(changeset, _step, _alter), do: changeset

  defp validate_range(changeset) do
    range_error(changeset, get_field(changeset, :step), get_field(changeset, :alter))
  end
end
