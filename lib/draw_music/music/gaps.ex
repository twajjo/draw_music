defmodule DrawMusic.Music.Gaps do
  @moduledoc """
  The rests that fill a measure's gaps: in voice 1 of each staff, and in any
  other voice that has notes in the measure. The rests have no ids; callers
  that store them give them ids, and the engraver draws them as implied.
  """

  alias DrawMusic.Music.{Duration, Measure, Rest}

  @spec rests(Measure.t(), pos_integer()) :: [Rest.t()]
  def rests(%Measure{} = measure, capacity) do
    Enum.flat_map(voices_in(measure), &voice_rests(measure, &1, capacity))
  end

  defp voices_in(measure) do
    Enum.uniq([{:treble, 1}, {:bass, 1} | Enum.map(measure.notes, &{&1.staff, &1.voice})])
  end

  defp voice_rests(measure, {staff, voice}, capacity) do
    occupied =
      for event <- measure.notes ++ measure.rests, event.staff == staff, event.voice == voice do
        {event.offset, event.offset + Duration.ticks(event.value, event.dots)}
      end
      |> Enum.sort()

    {gaps, cursor} =
      Enum.reduce(occupied, {[], 0}, fn {from, to}, {gaps, cursor} ->
        {add_gap(gaps, cursor, from), max(cursor, to)}
      end)

    gaps
    |> add_gap(cursor, capacity)
    |> Enum.flat_map(&rests_for_gap(&1, staff, voice))
  end

  defp add_gap(gaps, from, to) when to > from, do: [{from, to - from} | gaps]
  defp add_gap(gaps, _from, _to), do: gaps

  # Rests the way they're written: at each point, the longest undotted rest
  # that fits and starts on a multiple of its own length, so rests fall on
  # the beats (after a first-beat quarter in 4/4: a quarter, then a half).
  defp rests_for_gap({offset, len}, staff, voice), do: fill(offset, offset + len, staff, voice)

  defp fill(at, stop, _staff, _voice) when at >= stop, do: []

  defp fill(at, stop, staff, voice) do
    case Enum.find(Duration.values(), &fits_at?(&1, at, stop)) do
      nil ->
        []

      value ->
        rest = %Rest{staff: staff, voice: voice, offset: at, value: value, dots: 0}
        [rest | fill(at + Duration.ticks(value), stop, staff, voice)]
    end
  end

  defp fits_at?(value, at, stop) do
    ticks = Duration.ticks(value)
    ticks <= stop - at and rem(at, ticks) == 0
  end
end
