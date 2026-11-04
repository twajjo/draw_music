defmodule DrawMusic.Music.Duration do
  @moduledoc """
  Note values and their lengths in ticks (960 per quarter note).

  A dot adds half the base value; a second dot adds a further quarter.
  Every length is a whole number of ticks, so the shortest values take
  fewer dots: a 128th (30 ticks) at most one, a 256th (15) none.
  """

  @ppq 960
  @quarters_per_whole 4
  @max_dots 2

  @typedoc "A note value, whole through 256th."
  @type value ::
          :whole
          | :half
          | :quarter
          | :eighth
          | :sixteenth
          | :thirty_second
          | :sixty_fourth
          | :hundred_twenty_eighth
          | :two_hundred_fifty_sixth
  @values [
    :whole,
    :half,
    :quarter,
    :eighth,
    :sixteenth,
    :thirty_second,
    :sixty_fourth,
    :hundred_twenty_eighth,
    :two_hundred_fifty_sixth
  ]
  # The values every length was written with before the 128th and 256th:
  # lengths they can write keep splitting the way they always have.
  @common_values Enum.take_while(@values, &(&1 != :hundred_twenty_eighth))
  @base Enum.with_index(@values, fn value, halvings ->
          {value, div(@ppq * @quarters_per_whole, 2 ** halvings)}
        end)
  @flags %{
    eighth: 1,
    sixteenth: 2,
    thirty_second: 3,
    sixty_fourth: 4,
    hundred_twenty_eighth: 5,
    two_hundred_fifty_sixth: 6
  }
  # Further dots would need fractions of a tick.
  @dot_limits %{hundred_twenty_eighth: 1, two_hundred_fifty_sixth: 0}

  max_dots = fn value -> Map.get(@dot_limits, value, @max_dots) end
  dotted = fn base, dots -> Enum.sum(for dot <- 0..dots, do: div(base, 2 ** dot)) end

  # Every value/dots combination, longest first: of the common values, and
  # of all of them.
  candidates_of = fn values ->
    for {value, base} <- @base, value in values, dots <- 0..max_dots.(value) do
      {value, dots, dotted.(base, dots)}
    end
    |> Enum.sort_by(fn {_v, _d, ticks} -> ticks end, :desc)
  end

  @common_candidates candidates_of.(@common_values)
  @candidates candidates_of.(@values)
  @lengths Map.new(@candidates, fn {value, dots, ticks} -> {{value, dots}, ticks} end)

  # Every length is a multiple of a 256th. In those units the common
  # values' three shortest lengths are 4, 6 and 7, whose sums reach every
  # count except these; with the 256th (1) every count is reached.
  @unit Keyword.fetch!(@base, :two_hundred_fifty_sixth)
  @common_unreachable_units [1, 2, 3, 5, 9]

  @spec ppq() :: pos_integer()
  def ppq, do: @ppq

  @doc "How many dots any value may take, at most."
  @spec dot_counts() :: Range.t()
  def dot_counts, do: 0..@max_dots

  @doc "How many dots `value` may take."
  @spec dot_counts(value()) :: Range.t()
  def dot_counts(value), do: 0..Map.get(@dot_limits, value, @max_dots)

  @doc "Whether `value` can take `dots`."
  @spec dots_allowed?(value(), integer()) :: boolean()
  def dots_allowed?(value, dots), do: dots in dot_counts(value)

  @doc "Checks a note's or rest's `:dots` against what its `:value` may take."
  @spec validate_dots(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_dots(changeset) do
    case Ecto.Changeset.get_field(changeset, :value) do
      nil -> Ecto.Changeset.validate_inclusion(changeset, :dots, dot_counts())
      value -> Ecto.Changeset.validate_inclusion(changeset, :dots, dot_counts(value))
    end
  end

  @doc "Note values, longest first."
  @spec values() :: [value()]
  def values, do: @values

  @doc "Length of `value` with `dots` (as many as it may take) in ticks."
  @spec ticks(value()) :: pos_integer()
  @spec ticks(value(), 0..2) :: pos_integer()
  def ticks(value, dots \\ 0), do: Map.fetch!(@lengths, {value, dots})

  @doc "Number of flags (or beams) the value takes: 0 for quarter and longer."
  @spec flags(value()) :: 0..6
  def flags(value), do: Map.get(@flags, value, 0)

  @doc "Eighths and shorter can be beamed."
  @spec beamable?(value()) :: boolean()
  def beamable?(value), do: flags(value) > 0

  @doc """
  Splits a length in ticks into consecutive note values (to be tied), longest
  first. 128ths and 256ths are used only for lengths the longer values
  can't write. Returns `{:error, :unrepresentable}` when no combination of
  values adds up to it.
  """
  @spec decompose(non_neg_integer()) :: {:ok, [{value(), 0..2}]} | {:error, :unrepresentable}
  def decompose(0), do: {:ok, []}

  def decompose(ticks) when is_integer(ticks) and ticks > 0 do
    case {rem(ticks, @unit), div(ticks, @unit)} do
      {0, units} when units in @common_unreachable_units -> {:ok, take(ticks, :all)}
      {0, _units} -> {:ok, take(ticks, :common)}
      _fraction -> {:error, :unrepresentable}
    end
  end

  defp take(0, _values), do: []

  defp take(ticks, values) do
    {value, dots, len} =
      values
      |> candidates()
      |> Enum.find(fn {_v, _d, len} -> len <= ticks and representable?(ticks - len, values) end)

    [{value, dots} | take(ticks - len, values)]
  end

  defp candidates(:common), do: @common_candidates
  defp candidates(:all), do: @candidates

  defp representable?(ticks, :common) do
    rem(ticks, @unit) == 0 and div(ticks, @unit) not in @common_unreachable_units
  end

  defp representable?(ticks, :all), do: rem(ticks, @unit) == 0
end
