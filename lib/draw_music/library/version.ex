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
  alias DrawMusic.Music.{Context, Score}

  @defaults %Context{}
  @time_denominators Context.time_denominators()
  @tempo_range Context.tempo_range()
  @acoustic_grand_piano 0
  @max_program 127
  @max_label_length 120
  @max_tempo_text_length 60

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "composition_versions" do
    field :number, :integer
    field :label, :string
    field :time_num, :integer, default: @defaults.time_num
    field :time_den, :integer, default: @defaults.time_den
    field :time_symbol, Ecto.Enum, values: [:none, :common, :cut], default: @defaults.time_symbol
    field :tempo_bpm, :integer, default: @defaults.tempo_bpm
    field :tempo_text, :string
    # Length of an opening incomplete (anacrusis) bar, in score ticks; 0 = none.
    field :pickup_ticks, :integer, default: @defaults.pickup_ticks
    # General MIDI program number used for playback.
    field :instrument, :integer, default: @acoustic_grand_piano
    # Scores are always replaced whole (the editor saves a new %Score{}).
    embeds_one :score, Score, on_replace: :delete, defaults_to_struct: true

    belongs_to :key, Key

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          number: pos_integer() | nil,
          label: String.t() | nil,
          time_num: pos_integer(),
          time_den: pos_integer(),
          time_symbol: :none | :common | :cut,
          tempo_bpm: pos_integer(),
          tempo_text: String.t() | nil,
          pickup_ticks: non_neg_integer(),
          instrument: 0..127,
          score: Score.t(),
          key_id: Ecto.UUID.t() | nil,
          key: Key.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @fields [
    :label,
    :time_num,
    :time_den,
    :time_symbol,
    :tempo_bpm,
    :tempo_text,
    :pickup_ticks,
    :instrument
  ]

  @doc """
  Changeset for a version's content. `number` and `key_id` are set by
  `DrawMusic.Library`, never cast from input. `score` may be given as a
  `%DrawMusic.Music.Score{}` (from the editor) or as params (from storage or
  an imported file), which are validated.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(version, attrs) do
    version
    |> cast(attrs, @fields)
    |> put_score(attrs)
    |> validate_required([:number, :time_num, :time_den, :time_symbol, :tempo_bpm, :score])
    |> validate_length(:label, max: @max_label_length)
    |> validate_length(:tempo_text, max: @max_tempo_text_length)
    |> validate_number(:time_num,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: Context.max_time_num()
    )
    |> validate_inclusion(:time_den, @time_denominators)
    |> validate_time_symbol()
    |> validate_number(:tempo_bpm,
      greater_than_or_equal_to: @tempo_range.first,
      less_than_or_equal_to: @tempo_range.last
    )
    |> validate_number(:pickup_ticks, greater_than_or_equal_to: 0)
    |> validate_pickup()
    |> validate_number(:instrument,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: @max_program
    )
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

  defp validate_pickup(changeset) do
    pickup_error(
      changeset,
      get_field(changeset, :pickup_ticks),
      get_field(changeset, :time_num),
      get_field(changeset, :time_den)
    )
  end

  # A pickup bar is shorter than a full measure of a valid meter.
  defp pickup_error(changeset, pickup, num, den)
       when is_integer(pickup) and pickup > 0 and is_integer(num) and den in @time_denominators do
    if pickup >= Context.measure_ticks(%Context{time_num: num, time_den: den}) do
      add_error(changeset, :pickup_ticks, "must be shorter than a full measure")
    else
      changeset
    end
  end

  defp pickup_error(changeset, _pickup, _num, _den), do: changeset

  defp put_score(changeset, attrs) do
    case Map.get(attrs, :score, attrs["score"]) do
      %Score{} = score -> put_embed(changeset, :score, score)
      _params -> cast_embed(changeset, :score)
    end
  end
end
