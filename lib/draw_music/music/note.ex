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

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          staff: staff(),
          voice: 1..4,
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
    |> validate_inclusion(:voice, 1..4)
    |> validate_number(:offset, greater_than_or_equal_to: 0)
    |> validate_inclusion(:dots, 0..2)
    |> validate_inclusion(:alter, -2..2)
    |> validate_range()
  end

  defp validate_range(changeset) do
    step = get_field(changeset, :step)
    alter = get_field(changeset, :alter)

    if is_integer(step) and is_integer(alter) and not Pitch.in_range?(Pitch.midi(step, alter)) do
      add_error(changeset, :step, "is outside the piano's range (A0–C8)")
    else
      changeset
    end
  end

  @doc "Sounding pitch as a MIDI number."
  @spec midi(t()) :: integer()
  def midi(%__MODULE__{step: step, alter: alter}), do: Pitch.midi(step, alter)

  @doc "Length in ticks."
  @spec ticks(t()) :: pos_integer()
  def ticks(%__MODULE__{value: value, dots: dots}), do: Duration.ticks(value, dots)
end
