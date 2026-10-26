defmodule DrawMusic.Music.TempoMap do
  @moduledoc """
  How fast a score goes at every tick: the starting tempo (the context's)
  and the score's tempo changes, as stretches of steady or evenly changing
  tempo. Answers how many seconds lie between two ticks. A change takes
  over from the one before it, even part-way through a rit. or accel.

  Tempos count quarter notes per minute, as MIDI does.
  """

  alias DrawMusic.Music.{Context, Duration, PlaybackAnchor, Score, TempoChange, TempoSegment}

  @enforce_keys [:segments]
  defstruct [:segments]

  @type t :: %__MODULE__{segments: [TempoSegment.t()]}

  @seconds_per_minute 60
  # Within a rit. or accel., the playhead's anchors fall on every beat.
  @anchor_step Duration.ppq()

  @doc "The score's tempo map."
  @spec new(Score.t(), Context.t()) :: t()
  def new(%Score{tempos: tempos}, %Context{tempo_bpm: bpm}) do
    changes = Enum.sort_by(tempos, & &1.tick)
    next_ticks = Enum.map(tl(changes ++ [nil]), &(&1 && &1.tick))

    {segments, {tick, bpm}} =
      changes
      |> Enum.zip(next_ticks)
      |> Enum.flat_map_reduce({0, bpm}, &segments_for/2)

    %__MODULE__{segments: segments ++ [steady(tick, :infinity, bpm)]}
  end

  # The steady stretch up to a change, then the change's own ramp, if any.
  defp segments_for({change, next_tick}, {tick, bpm}) do
    before = if change.tick > tick, do: [steady(tick, change.tick, bpm)], else: []

    if TempoChange.gradual?(change) do
      stop = min(change.to_tick, next_tick || change.to_tick)
      reached = bpm_along(change, stop)
      ramp = %TempoSegment{start: change.tick, stop: stop, from_bpm: change.bpm, to_bpm: reached}
      {before ++ [ramp], {stop, reached}}
    else
      {before, {change.tick, change.bpm}}
    end
  end

  defp steady(start, stop, bpm),
    do: %TempoSegment{start: start, stop: stop, from_bpm: bpm, to_bpm: bpm}

  defp bpm_along(%TempoChange{} = change, tick) do
    change.bpm +
      (change.to_bpm - change.bpm) * (tick - change.tick) / (change.to_tick - change.tick)
  end

  @doc "The tempo at `tick`, to the nearest BPM."
  @spec bpm_at(t(), non_neg_integer()) :: pos_integer()
  def bpm_at(%__MODULE__{segments: segments}, tick) do
    segment = Enum.find(segments, &(&1.stop == :infinity or tick < &1.stop))

    case segment do
      %TempoSegment{from_bpm: bpm, to_bpm: bpm} ->
        round(bpm)

      %TempoSegment{} ->
        along = (tick - segment.start) / (segment.stop - segment.start)
        round(segment.from_bpm + (segment.to_bpm - segment.from_bpm) * along)
    end
  end

  @doc "Seconds from tick `from` to tick `to` (`from <= to`)."
  @spec seconds(t(), non_neg_integer(), non_neg_integer()) :: float()
  def seconds(%__MODULE__{segments: segments}, from, to) do
    segments
    |> Enum.map(&seconds_within(&1, max(from, &1.start), min_stop(to, &1.stop)))
    |> Enum.sum()
    |> Kernel.*(1.0)
  end

  defp min_stop(to, :infinity), do: to
  defp min_stop(to, stop), do: min(to, stop)

  defp seconds_within(_segment, a, b) when b <= a, do: 0.0

  defp seconds_within(%TempoSegment{from_bpm: bpm, to_bpm: bpm}, a, b) do
    (b - a) * @seconds_per_minute / (bpm * Duration.ppq())
  end

  # The tempo moves evenly with the ticks, so time is the log of its ratio.
  defp seconds_within(%TempoSegment{} = segment, a, b) do
    slope = (segment.to_bpm - segment.from_bpm) / (segment.stop - segment.start)
    bpm_at = fn tick -> segment.from_bpm + slope * (tick - segment.start) end
    @seconds_per_minute / (Duration.ppq() * slope) * :math.log(bpm_at.(b) / bpm_at.(a))
  end

  @doc """
  Ticks from `from` to `to` paired with their seconds after `from`: every
  tempo change between, and every beat inside a rit. or accel. The browser
  maps the clock to the score by interpolating between them.
  """
  @spec anchors(t(), non_neg_integer(), non_neg_integer()) :: [PlaybackAnchor.t()]
  def anchors(%__MODULE__{segments: segments} = map, from, to) do
    inside =
      Enum.flat_map(segments, fn segment ->
        [segment.start | ramp_beats(segment)]
      end)

    ticks =
      [from, to | Enum.filter(inside, &(&1 > from and &1 < to))]
      |> Enum.uniq()
      |> Enum.sort()

    {anchors, _last} =
      Enum.map_reduce(ticks, {from, 0.0}, fn tick, {previous, elapsed} ->
        elapsed = elapsed + seconds(map, previous, tick)
        {%PlaybackAnchor{seconds: elapsed, tick: tick}, {tick, elapsed}}
      end)

    anchors
  end

  defp ramp_beats(%TempoSegment{from_bpm: bpm, to_bpm: bpm}), do: []

  defp ramp_beats(%TempoSegment{start: start, stop: stop}) do
    Enum.to_list((start + @anchor_step)..(stop - 1)//@anchor_step) ++ [stop]
  end
end
