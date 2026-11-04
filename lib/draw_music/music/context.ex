defmodule DrawMusic.Music.Context do
  @moduledoc """
  The settings a score is read against: key, time signature (and how it is
  written: digits, common or cut time), pickup and tempo. They live on the
  version, not in the score itself.
  """

  alias DrawMusic.Music.Duration

  @time_denominators [1, 2, 4, 8, 16, 32, 64]
  @max_time_num 32
  @tempo_range 20..400
  @beats_per_compound_beat 3

  defstruct sf: 0,
            mode: :major,
            time_num: 4,
            time_den: 4,
            time_symbol: :none,
            pickup_ticks: 0,
            tempo_bpm: 100

  @type t :: %__MODULE__{
          sf: -7..7,
          mode: :major | :minor,
          time_num: pos_integer(),
          time_den: pos_integer(),
          time_symbol: :none | :common | :cut,
          pickup_ticks: non_neg_integer(),
          tempo_bpm: pos_integer()
        }

  @doc "Time-signature denominators a score may use."
  @spec time_denominators() :: [pos_integer()]
  def time_denominators, do: @time_denominators

  @spec max_time_num() :: pos_integer()
  def max_time_num, do: @max_time_num

  @doc "Tempos a score may use, in beats per minute."
  @spec tempo_range() :: Range.t()
  def tempo_range, do: @tempo_range

  @doc "Builds a context from a version with its key loaded."
  @spec from_version(DrawMusic.Library.Version.t()) :: t()
  def from_version(%{key: %{sf: sf, mode: mode}} = version) do
    %__MODULE__{
      sf: sf,
      mode: mode,
      time_num: version.time_num,
      time_den: version.time_den,
      time_symbol: version.time_symbol,
      pickup_ticks: version.pickup_ticks,
      tempo_bpm: version.tempo_bpm
    }
  end

  @doc "Length of a full measure in ticks."
  @spec measure_ticks(t()) :: pos_integer()
  def measure_ticks(%__MODULE__{time_num: num} = ctx), do: num * beat_ticks(ctx)

  @doc "One time-signature unit (the denominator's note value) in ticks."
  @spec beat_ticks(t()) :: pos_integer()
  def beat_ticks(%__MODULE__{time_den: den}), do: div(Duration.ticks(:whole), den)

  @doc "6/8, 9/8, 12/8 and the like: beats divide into three."
  @spec compound?(t()) :: boolean()
  def compound?(%__MODULE__{time_num: num}) do
    num > @beats_per_compound_beat and rem(num, @beats_per_compound_beat) == 0
  end

  @doc "Span that beamed notes are grouped by: the felt beat."
  @spec beam_group_ticks(t()) :: pos_integer()
  def beam_group_ticks(ctx) do
    if compound?(ctx), do: @beats_per_compound_beat * beat_ticks(ctx), else: beat_ticks(ctx)
  end

  @doc "Capacity of measure `index`: the pickup length for an opening pickup bar."
  @spec capacity(t(), non_neg_integer()) :: pos_integer()
  def capacity(%__MODULE__{pickup_ticks: pickup}, 0) when pickup > 0, do: pickup
  def capacity(ctx, _index), do: measure_ticks(ctx)

  @doc "Total length of the first `count` measures."
  @spec span(t(), non_neg_integer()) :: non_neg_integer()
  def span(_ctx, 0), do: 0
  def span(ctx, count), do: capacity(ctx, 0) + (count - 1) * measure_ticks(ctx)
end
