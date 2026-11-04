defmodule DrawMusic.Music.Beaming do
  @moduledoc """
  Groups eighths and shorter notes under beams, separately for each voice of
  each staff. A group runs over consecutive notes (a chord counts as one)
  within one felt beat: a quarter in simple meters, a dotted quarter in
  compound meters such as 6/8. Rests, longer notes, gaps and beat boundaries
  end a group. A pickup measure's beats are counted back from its end.
  """

  alias DrawMusic.Music.{BeamGroup, Context, Duration, Measure}

  @beamable Enum.filter(Duration.values(), &Duration.beamable?/1)
  @min_group 2

  @doc """
  Beam groups of measure `index`, each with at least two notes or chords.
  """
  @spec groups(Measure.t(), Context.t(), non_neg_integer()) :: [BeamGroup.t()]
  def groups(%Measure{} = measure, %Context{} = ctx, index) do
    shift = Context.measure_ticks(ctx) - Context.capacity(ctx, index)
    span = Context.beam_group_ticks(ctx)

    lines =
      (measure.notes ++ measure.rests)
      |> Enum.map(&{&1.staff, &1.voice})
      |> Enum.uniq()
      |> Enum.sort()

    for {staff, voice} <- lines,
        offsets <- line_groups(measure, staff, voice, &div(&1 + shift, span)) do
      %BeamGroup{staff: staff, voice: voice, offsets: offsets}
    end
  end

  defp line_groups(measure, staff, voice, beat_of) do
    notes =
      for n <- measure.notes, n.staff == staff, n.voice == voice do
        {n.offset, :note, n.value, n.dots}
      end

    rests =
      for r <- measure.rests, r.staff == staff, r.voice == voice do
        {r.offset, :rest, r.value, r.dots}
      end

    (Enum.uniq_by(notes, &elem(&1, 0)) ++ rests)
    |> Enum.sort()
    |> Enum.reduce({[], []}, fn event, {groups, run} -> step(event, groups, run, beat_of) end)
    |> close()
    |> Enum.reverse()
  end

  defp step({offset, :note, value, dots}, groups, run, beat_of) when value in @beamable do
    extend(groups, run, {offset, value, dots}, continues?(run, offset, beat_of))
  end

  # Rests and unbeamable notes end the run.
  defp step(_event, groups, run, _beat_of), do: {close_run(groups, run), []}

  defp extend(groups, run, note, true = _continues?), do: {groups, [note | run]}
  defp extend(groups, run, note, false), do: {close_run(groups, run), [note]}

  defp continues?([], _offset, _beat_of), do: false

  defp continues?([{prev, value, dots} | _] = run, offset, beat_of) do
    {first, _v, _d} = List.last(run)
    prev + Duration.ticks(value, dots) == offset and beat_of.(first) == beat_of.(offset)
  end

  defp close({groups, run}), do: close_run(groups, run)

  defp close_run(groups, run) when length(run) >= @min_group do
    offsets =
      run
      |> Enum.reverse()
      |> Enum.map(&elem(&1, 0))

    [offsets | groups]
  end

  defp close_run(groups, _run), do: groups
end
