defmodule DrawMusic.Music.Duration do
  @moduledoc """
  Note values and their lengths in ticks (960 per quarter note).

  A dot adds half the base value; a second dot adds a further quarter.
  Every length, down to a double-dotted 64th (105 ticks), is a whole number
  of ticks.
  """

  @ppq 960
  @base [
    whole: 3840,
    half: 1920,
    quarter: 960,
    eighth: 480,
    sixteenth: 240,
    thirty_second: 120,
    sixty_fourth: 60
  ]
  @values Keyword.keys(@base)

  @typedoc "A note value, whole through 64th."
  @type value :: :whole | :half | :quarter | :eighth | :sixteenth | :thirty_second | :sixty_fourth
  @flags %{eighth: 1, sixteenth: 2, thirty_second: 3, sixty_fourth: 4}

  # Every value/dots combination, longest first.
  @candidates (for {value, base} <- @base, dots <- 0..2 do
                 {value, dots,
                  base + if(dots >= 1, do: div(base, 2), else: 0) +
                    if(dots == 2, do: div(base, 4), else: 0)}
               end)
              |> Enum.sort_by(fn {_v, _d, ticks} -> ticks end, :desc)

  @spec ppq() :: pos_integer()
  def ppq, do: @ppq

  @doc "Note values, longest first."
  @spec values() :: [value()]
  def values, do: @values

  @doc "Length of `value` with `dots` (0..2) in ticks."
  @spec ticks(value()) :: pos_integer()
  @spec ticks(value(), 0..2) :: pos_integer()
  def ticks(value, dots \\ 0) when dots in 0..2 do
    base = Keyword.fetch!(@base, value)

    case dots do
      0 -> base
      1 -> base + div(base, 2)
      2 -> base + div(base, 2) + div(base, 4)
    end
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

  # All lengths are multiples of 15 ticks. In those units the three shortest
  # values are 4, 6 and 7, which can make every number from 10 up, plus
  # 4, 6, 7 and 8 — so only 1, 2, 3, 5 and 9 units are impossible.
  defp representable?(0), do: true
  defp representable?(ticks) when rem(ticks, 15) != 0, do: false

  defp representable?(ticks) do
    units = div(ticks, 15)
    units >= 4 and units not in [5, 9]
  end
end
