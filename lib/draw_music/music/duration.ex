defmodule DrawMusic.Music.Duration do
  @moduledoc """
  Note values and their lengths in ticks (960 per quarter note).

  A dot adds half the base value; a second dot adds a further quarter.
  Every length, down to a double-dotted 64th (105 ticks), is a whole number
  of ticks.
  """

  @ppq 960
  @quarters_per_whole 4
  @max_dots 2

  @typedoc "A note value, whole through 64th."
  @type value :: :whole | :half | :quarter | :eighth | :sixteenth | :thirty_second | :sixty_fourth
  @values [:whole, :half, :quarter, :eighth, :sixteenth, :thirty_second, :sixty_fourth]
  @base Enum.with_index(@values, fn value, halvings ->
          {value, div(@ppq * @quarters_per_whole, 2 ** halvings)}
        end)
  @flags %{eighth: 1, sixteenth: 2, thirty_second: 3, sixty_fourth: 4}

  dotted = fn base, dots -> Enum.sum(for dot <- 0..dots, do: div(base, 2 ** dot)) end

  # Every value/dots combination, longest first.
  @candidates (for {value, base} <- @base, dots <- 0..@max_dots do
                 {value, dots, dotted.(base, dots)}
               end)
              |> Enum.sort_by(fn {_v, _d, ticks} -> ticks end, :desc)

  # Every length is a multiple of the shortest dot increment (a 64th's
  # quarter). In those units the three shortest lengths are 4, 6 and 7,
  # whose sums reach every count except these.
  @unit div(Keyword.fetch!(@base, :sixty_fourth), 2 ** @max_dots)
  @unreachable_units [1, 2, 3, 5, 9]

  @spec ppq() :: pos_integer()
  def ppq, do: @ppq

  @doc "How many dots a value may take."
  @spec dot_counts() :: Range.t()
  def dot_counts, do: 0..@max_dots

  @doc "Note values, longest first."
  @spec values() :: [value()]
  def values, do: @values

  @doc "Length of `value` with `dots` (0..2) in ticks."
  @spec ticks(value()) :: pos_integer()
  @spec ticks(value(), 0..2) :: pos_integer()
  def ticks(value, dots \\ 0) when dots in 0..@max_dots do
    base = Keyword.fetch!(@base, value)
    Enum.sum(for dot <- 0..dots, do: div(base, 2 ** dot))
  end

  @doc "Number of flags (or beams) the value takes: 0 for quarter and longer."
  @spec flags(value()) :: 0..4
  def flags(value), do: Map.get(@flags, value, 0)

  @doc "Eighths and shorter can be beamed."
  @spec beamable?(value()) :: boolean()
  def beamable?(value), do: flags(value) > 0

  @doc """
  Splits a length in ticks into consecutive note values (to be tied), longest
  first. Returns `{:error, :unrepresentable}` when no combination of values
  adds up to it.
  """
  @spec decompose(non_neg_integer()) :: {:ok, [{value(), 0..2}]} | {:error, :unrepresentable}
  def decompose(0), do: {:ok, []}

  def decompose(ticks) when is_integer(ticks) and ticks > 0 do
    if representable?(ticks), do: {:ok, take(ticks)}, else: {:error, :unrepresentable}
  end

  defp take(0), do: []

  defp take(ticks) do
    {value, dots, len} =
      Enum.find(@candidates, fn {_v, _d, len} -> len <= ticks and representable?(ticks - len) end)

    [{value, dots} | take(ticks - len)]
  end

  defp representable?(ticks) do
    rem(ticks, @unit) == 0 and div(ticks, @unit) not in @unreachable_units
  end
end
