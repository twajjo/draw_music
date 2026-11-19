defmodule DrawMusic.Music.Gaps do
  @moduledoc """
  The rests that fill a measure's gaps: in voice 1 of each staff, and in any
  other voice that has notes in the measure. They are `filler` rests with no
  ids; callers that store them give them ids. The engraver draws any gap
  left unfilled (a score not yet opened for editing) as implied rests.

  Rests are written the way engravers write them: they show the beats.

    * **Simple meters** (4/4, 3/4, 2/2): at each point the longest plain
      rest that fits and starts on a multiple of its own length, so a half
      rest in 4/4 starts on beat 1 or 3 and the middle of the bar always
      shows (beats 2–3 are two quarter rests).
    * **Compound meters** (6/8, 9/8, 12/8), where a beat is a dotted
      quarter: a silent beat is a dotted quarter rest; two beats starting
      on beat 1 or 3 a dotted half rest, four a dotted whole. Inside a beat,
      plain rests aligned to the beat's start, so none crosses into the next
      beat (after a first eighth: two eighth rests).
    * **An empty bar** is one rest when one value fills it (a dotted half
      in 3/4), drawn as a whole-bar rest.
  """

  alias DrawMusic.Music.{Context, Duration, Measure, Rest}

  @doc "The filler rests for `measure`'s gaps, `capacity` long, in `ctx`'s meter."
  @spec rests(Measure.t(), pos_integer(), Context.t()) :: [Rest.t()]
  def rests(%Measure{} = measure, capacity, %Context{} = ctx) do
    beat = if Context.compound?(ctx), do: 3 * Context.beat_ticks(ctx)
    Enum.flat_map(voices_in(measure), &voice_rests(measure, &1, capacity, beat))
  end

  defp add_gap(gaps, from, to) when to > from, do: [{from, to - from} | gaps]
  defp add_gap(gaps, _from, _to), do: gaps

  # Compound meters, beat by beat (`beat` is a dotted quarter's ticks, or
  # the like): whole beats as dotted rests, part of a beat as plain ones.
  defp compound_fill(at, stop, _beat, _place) when at >= stop, do: []

  defp compound_fill(at, stop, beat, place) when rem(at, beat) == 0 and stop - at >= beat do
    ticks =
      Enum.find([4 * beat, 2 * beat, beat], &(&1 <= stop - at and rem(at, &1) == 0))

    {:ok, [{value, dots}]} = Duration.decompose(ticks)
    [filler(place, at, value, dots) | compound_fill(at + ticks, stop, beat, place)]
  end

  defp compound_fill(at, stop, beat, place) do
    beat_start = at - rem(at, beat)
    beat_end = min(stop, beat_start + beat)
    fill(at, beat_end, beat_start, place) ++ compound_fill(beat_end, stop, beat, place)
  end

  # Plain rests from `at` to `stop`: each the longest that fits and starts
  # a multiple of its own length after `origin`.
  defp fill(at, stop, _origin, _place) when at >= stop, do: []

  defp fill(at, stop, origin, place) do
    case Enum.find(Duration.values(), &fits_at?(&1, at - origin, stop - at)) do
      nil ->
        []

      value ->
        [filler(place, at, value, 0) | fill(at + Duration.ticks(value), stop, origin, place)]
    end
  end

  defp filler({staff, voice}, offset, value, dots) do
    %Rest{staff: staff, voice: voice, offset: offset, value: value, dots: dots, filler: true}
  end

  defp fits_at?(value, from_origin, room) do
    ticks = Duration.ticks(value)
    ticks <= room and rem(from_origin, ticks) == 0
  end

  # An empty bar is one rest when one value fills it.
  defp rests_for_gap({0, capacity}, place, capacity, beat) do
    case Duration.decompose(capacity) do
      {:ok, [{value, dots}]} -> [filler(place, 0, value, dots)]
      _several -> written(0, capacity, place, beat)
    end
  end

  defp rests_for_gap({offset, len}, place, _capacity, beat) do
    written(offset, offset + len, place, beat)
  end

  defp voice_rests(measure, {staff, voice} = place, capacity, beat) do
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
    |> Enum.flat_map(&rests_for_gap(&1, place, capacity, beat))
  end

  defp voices_in(measure) do
    Enum.uniq([{:treble, 1}, {:bass, 1} | Enum.map(measure.notes, &{&1.staff, &1.voice})])
  end

  # The rests for the time from `at` to `stop`: by beats in a compound
  # meter (`beat`), else plain rests aligned to the bar.
  defp written(at, stop, place, nil = _beat), do: fill(at, stop, 0, place)
  defp written(at, stop, place, beat), do: compound_fill(at, stop, beat, place)
end
