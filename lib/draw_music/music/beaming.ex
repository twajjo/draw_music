defmodule DrawMusic.Music.Beaming do
  @moduledoc """
  Groups eighths and shorter notes under beams, separately for each voice of
  each staff. A group runs over consecutive notes (a chord counts as one)
  within one felt beat: a quarter in simple meters, a dotted quarter in
  compound meters such as 6/8. Rests, longer notes, gaps and beat boundaries
  end a group. A pickup measure's beats are counted back from its end.
  """

  alias DrawMusic.Music.{Context, Duration, Measure}

  @doc """
  Beam groups of measure `index`, as
  `[%{staff: staff, voice: voice, offsets: [offset, ...]}]`, each with at
  least two notes or chords.
  """
  def groups(%Measure{} = measure, %Context{} = ctx, index) do
    shift = Context.measure_ticks(ctx) - Context.capacity(ctx, index)
    span = Context.beam_group_ticks(ctx)

    lines =
      (measure.notes ++ measure.rests)
      |> Enum.map(&{&1.staff, &1.voice})
      |> Enum.uniq()
      |> Enum.sort()

    for {staff, voice} <- lines,
        offsets <- line_groups(measure, staff, voice, &div(&1 + shift, span)),
        do: %{staff: staff, voice: voice, offsets: offsets}
  end

  defp line_groups(measure, staff, voice, beat_of) do
    notes =
      for n <- measure.notes,
          n.staff == staff,
          n.voice == voice,
          do: {n.offset, :note, n.value, n.dots}

    rests =
      for r <- measure.rests,
          r.staff == staff,
          r.voice == voice,
          do: {r.offset, :rest, r.value, r.dots}

    (Enum.uniq_by(notes, &elem(&1, 0)) ++ rests)
    |> Enum.sort()
    |> Enum.reduce({[], []}, fn event, {groups, run} -> step(event, groups, run, beat_of) end)
    |> close()
    |> Enum.reverse()
  end

  defp step({offset, :note, value, dots}, groups, run, beat_of) do
    cond do
      not Duration.beamable?(value) -> {close_run(groups, run), []}
      continues?(run, offset, beat_of) -> {groups, [{offset, value, dots} | run]}
      true -> {close_run(groups, run), [{offset, value, dots}]}
    end
  end

  defp step({_offset, :rest, _value, _dots}, groups, run, _beat_of),
    do: {close_run(groups, run), []}

  defp continues?([], _offset, _beat_of), do: false

  defp continues?([{prev, value, dots} | _] = run, offset, beat_of) do
    {first, _v, _d} = List.last(run)
    prev + Duration.ticks(value, dots) == offset and beat_of.(first) == beat_of.(offset)
  end

  defp close({groups, run}), do: close_run(groups, run)

  defp close_run(groups, run) when length(run) >= 2,
    do: [run |> Enum.reverse() |> Enum.map(&elem(&1, 0)) | groups]

  defp close_run(groups, _run), do: groups
end
