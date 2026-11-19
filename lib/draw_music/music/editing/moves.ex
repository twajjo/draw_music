defmodule DrawMusic.Music.Editing.Moves do
  @moduledoc """
  Moving a selection with ← and →, for `DrawMusic.Music.Editing` (whose
  moduledoc has the score's rules). The selection moves **whole**: no
  selected note or rest is ever split or tied over a bar line by the move.
  See plans/moving-selections.md.

  One step passes the item(s) beside the selection, on each staff and
  voice it is on (its "lanes"), and the music passed moves the other way
  to fill the place it left. The step grows, whole item by whole item,
  until every item of the selection lands inside one bar, and every rest
  in it lands where the rules for rests allow
  (`DrawMusic.Music.Gaps.rest_allowed?/3`: in 4/4 a half rest on beat 1 or
  3, never across beats 2–3).

  The music passed is not selected: its notes may be split and tied over a
  bar line, and its rests are rewritten. Selected rests keep their own
  value: the selection is the selection.
  """

  alias DrawMusic.Music.{Context, Editing, Entry, Fillers, Gaps, Rest, Score, Ties, Timeline}
  alias DrawMusic.Music.Editing.Rebuild

  @doc """
  Moves the notes and rests `ids` one step `:earlier` or `:later` (see the
  moduledoc). Returns the same ids, to keep them selected. With nowhere to
  go (the start or the end of the score), nothing changes. An item on the
  selection's lanes straddling its start or end refuses the move
  (`:overlap`).
  """
  @spec step(Score.t(), Context.t(), [Editing.id()], :earlier | :later) ::
          {:ok, Score.t(), [Editing.id()]} | {:error, Editing.reason()}
  def step(%Score{} = score, %Context{} = ctx, ids, direction)
      when direction in [:earlier, :later] do
    entries = Timeline.flatten(score, ctx)
    ids = MapSet.new(ids)

    case Enum.filter(entries, &(&1.event.id in ids)) do
      [] -> {:ok, score, []}
      selected -> step_block(score, ctx, entries, selected, direction)
    end
  end

  # The music passed is silence where it is a rest: rewritten, not kept.
  defp as_filler(%Rest{} = rest), do: %{rest | filler: true}
  defp as_filler(note), do: note

  # The bar `{start, capacity}` holding tick `at`, or nil past the end.
  defp bar_at(bars, at) do
    Enum.find(bars, fn {start, capacity} -> at >= start and at < start + capacity end)
  end

  # Ticks where an item starts or ends on every one of `lanes`, past the
  # block's edge in `direction`, nearest first.
  defp common_edges(outside, lanes, {from, to}, direction) do
    lanes
    |> Enum.map(&edges_on(outside, &1))
    |> Enum.reduce(&MapSet.intersection/2)
    |> Enum.filter(&past?(&1, {from, to}, direction))
    |> Enum.sort(if direction == :later, do: :asc, else: :desc)
  end

  defp edges_on(entries, lane) do
    for entry <- entries,
        lane(entry) == lane,
        edge <- [entry.start, Entry.end_tick(entry)],
        into: MapSet.new(),
        do: edge
  end

  # How far the block moves: to the nearest common edge where every item
  # in it lands inside one bar (and every rest where it's allowed); nil if
  # there's none.
  defp find_step(ctx, bars, {outside, lanes, block}, {from, to}, direction) do
    outside
    |> common_edges(lanes, {from, to}, direction)
    |> Enum.map(&if(direction == :later, do: &1 - to, else: &1 - from))
    |> Enum.find(fn distance -> Enum.all?(block, &lands?(ctx, bars, &1, distance)) end)
  end

  # Whether `entry`, moved by `distance`, lies inside one bar (and, a rest,
  # starts where a rest of its length may).
  defp lands?(ctx, bars, entry, distance) do
    start = entry.start + distance

    case bar_at(bars, start) do
      nil ->
        false

      {bar_start, capacity} ->
        start + entry.ticks <= bar_start + capacity and
          (entry.kind == :note or Gaps.rest_allowed?(ctx, start - bar_start, entry.ticks))
    end
  end

  defp lane(entry), do: {entry.event.staff, entry.event.voice}

  # The block moves by `distance`; the music it passes moves the other way
  # by the block's length, its rests rewritten.
  defp moved(score, ctx, {block, outside, others}, {from, to}, distance, ids) do
    {passed_from, passed_to, back} =
      if distance > 0,
        do: {to, to + distance, from - to},
        else: {from + distance, from, to - from}

    {passed, still} =
      Enum.split_with(outside, &(&1.start >= passed_from and Entry.end_tick(&1) <= passed_to))

    moved_block =
      for e <- block, do: %{e | start: e.start + distance, event: Fillers.claim(e.event)}

    moved_passed = for e <- passed, do: %{e | start: e.start + back, event: as_filler(e.event)}
    entries = Ties.merge(moved_block ++ moved_passed ++ still ++ others)

    with {:ok, score} <- Rebuild.rebuild(score, ctx, entries), do: {:ok, score, ids}
  end

  defp past?(edge, {_from, to}, :later), do: edge > to
  defp past?(edge, {from, _to}, :earlier), do: edge < from

  # The block: the selection's time on its lanes, everything in it moving
  # together.
  defp step_block(score, ctx, entries, selected, direction) do
    lanes = selected |> Enum.map(&lane/1) |> Enum.uniq()
    from = selected |> Enum.map(& &1.start) |> Enum.min()
    to = selected |> Enum.map(&Entry.end_tick/1) |> Enum.max()
    {on_lanes, others} = Enum.split_with(entries, &(lane(&1) in lanes))
    ids = Enum.map(selected, & &1.event.id)

    if Enum.any?(on_lanes, &straddles?(&1, from, to)) do
      {:error, :overlap}
    else
      {block, outside} =
        Enum.split_with(on_lanes, &(&1.start >= from and Entry.end_tick(&1) <= to))

      bars = Timeline.bars(score, ctx)

      case find_step(ctx, bars, {outside, lanes, block}, {from, to}, direction) do
        nil -> {:ok, score, ids}
        distance -> moved(score, ctx, {block, outside, others}, {from, to}, distance, ids)
      end
    end
  end

  # An item crossing the block's start or end.
  defp straddles?(entry, from, to) do
    crosses? = fn edge ->
      entry.start < edge and edge < Entry.end_tick(entry)
    end

    crosses?.(from) or crosses?.(to)
  end
end
