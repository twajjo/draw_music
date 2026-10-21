defmodule DrawMusic.Library.Version do
  @moduledoc """
  One numbered rendition of a composition in a given key: its starting time
  signature, tempo, pickup, playback instrument and the score itself.
  Numbers start at 1 and are unique within a key.

  The time signature and tempo here are the *starting* values; changes partway
  through a piece live in the score.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias DrawMusic.Library.Key

  @time_denominators [1, 2, 4, 8, 16, 32, 64]

  schema "composition_versions" do
    field :number, :integer
    field :label, :string
    field :time_num, :integer, default: 4
    field :time_den, :integer, default: 4
    field :time_symbol, Ecto.Enum, values: [:none, :common, :cut], default: :none
    field :tempo_bpm, :integer, default: 100
    field :tempo_text, :string
    # Length of an opening incomplete (anacrusis) bar, in score ticks; 0 = none.
    field :pickup_ticks, :integer, default: 0
    # General MIDI program number used for playback; 0 = acoustic grand piano.
    field :instrument, :integer, default: 0
    field :score, :map, default: %{}

    belongs_to :key, Key

    timestamps(type: :utc_datetime)
  end

  @fields [
    :label,
    :time_num,
    :time_den,
    :time_symbol,
    :tempo_bpm,
    :tempo_text,
    :pickup_ticks,
    :instrument,
    :score
  ]

  @doc """
  Changeset for a version's content. `number` and `key_id` are set by
  `DrawMusic.Library`, never cast from input.
  """
  def changeset(version, attrs) do
    version
    |> cast(attrs, @fields)
    |> validate_required([:number, :time_num, :time_den, :time_symbol, :tempo_bpm, :score])
    |> validate_length(:label, max: 120)
    |> validate_length(:tempo_text, max: 60)
    |> validate_number(:time_num, greater_than_or_equal_to: 1, less_than_or_equal_to: 32)
    |> validate_inclusion(:time_den, @time_denominators)
    |> validate_time_symbol()
    |> validate_number(:tempo_bpm, greater_than_or_equal_to: 20, less_than_or_equal_to: 400)
    |> validate_number(:pickup_ticks, greater_than_or_equal_to: 0)
    |> validate_number(:instrument, greater_than_or_equal_to: 0, less_than_or_equal_to: 127)
    |> unique_constraint([:key_id, :number], name: :composition_versions_key_id_number_index)
  end

  # Common time (𝄴) only stands for 4/4 and cut time (𝄵) only for 2/2.
  defp validate_time_symbol(changeset) do
    symbol = get_field(changeset, :time_symbol)
    meter = {get_field(changeset, :time_num), get_field(changeset, :time_den)}

    case {symbol, meter} do
      {:common, m} when m != {4, 4} -> add_error(changeset, :time_symbol, "common time is 4/4")
      {:cut, m} when m != {2, 2} -> add_error(changeset, :time_symbol, "cut time is 2/2")
      _ -> changeset
    end
  end
end
