defmodule DrawMusic.Music.Editing.Time do
  @moduledoc """
  Edits that move music in time, for `DrawMusic.Music.Editing` (whose
  moduledoc has the score's rules): removing and deleting, shifting,
  inserting time, playing backwards, re-barring, and selecting a range.
  Those that move music (`shift/4`, `insert_time/5`, `delete/3`,
  `rebar_to/3`) also merge the tied pieces of a lone note back into one
  where they follow each other (`DrawMusic.Music.Ties.merge/1`).
  """

  alias DrawMusic.Music.{
    Context,
    Editing,
    Entry,
    Fillers,
    Note,
    Score,
    Spans,
    Ties,
    Timeline
  }

  alias DrawMusic.Music.Editing.Rebuild

  @doc """
  `entries` with the time from `from` to `to` cleared on each of `staves`,
  in every voice: an item sounding into it from earlier is shortened to
  end at `from`, and every other item touching it goes. Nothing moves; the
  rebuild refills with rests whatever is left uncovered.
  """
  @spec clear_span([Entry.t()], [Note.staff()], non_neg_integer(), non_neg_integer()) ::
          [Entry.t()]
  def clear_span(entries, staves, from, to) do
    Enum.flat_map(entries, fn entry ->
      touched? =
        entry.event.staff in staves and entry.start < to and from < Entry.end_tick(entry)

      if touched?, do: trim_before(entry, from), else: [entry]
    end)
  end

  @doc "Clears the time from `from` to `to` on `staves` (see `clear_span/4`), for overwriting."
  @spec clear_time(Score.t(), Context.t(), non_neg_integer(), non_neg_integer(), [Note.staff()]) ::
          Editing.result()
  def clear_time(%Score{} = score, %Context{} = ctx, from, to, staves) do
    Rebuild.rebuild(score, ctx, clear_span(Timeline.flatten(score, ctx), staves, from, to))
  end

  @doc """
  Deletes events and closes the gap on each staff they were on: every
  later event on that staff moves left by the time emptied before it. Time
  another voice on the staff still sounds (with a note or a placed rest) is
  not a gap. Deleting a filler rest closes its gap.
  """
  @spec delete(Score.t(), Context.t(), [Editing.id()]) :: Editing.result()
  def delete(%Score{} = score, %Context{} = ctx, ids) do
    {gone, kept} = Entry.select(Timeline.flatten(score, ctx), ids)

    gaps =
      gone
      |> Enum.group_by(& &1.event.staff)
      |> Map.new(fn {staff, removed} ->
        covers = Enum.filter(kept, &(&1.event.staff == staff and not Fillers.filler?(&1)))
        {staff, Spans.emptied(removed, covers)}
      end)

    shifted =
      Enum.map(kept, fn entry ->
        closed =
          for {from, to} <- Map.get(gaps, entry.event.staff, []), to <= entry.start do
            to - from
          end

        %{entry | start: entry.start - Enum.sum(closed)}
      end)

    Rebuild.rebuild(score, ctx, Ties.merge(shifted))
  end

  @doc """
  Where an insert at tick `at` on `staff` lands, like a text cursor among
  characters: every note and rest is one, the rests that end the piece
  included, so it lands where it's put, never inside an item. Where a note
  or rest starts, there (in front of it); inside a note, where it ends;
  inside a rest, in front of it, so it stays in the bar it was put in.
  """
  @spec insert_point(Score.t(), Context.t(), Note.staff(), non_neg_integer()) ::
          non_neg_integer()
  def insert_point(%Score{} = score, %Context{} = ctx, staff, at) do
    spans =
      for %{event: %{staff: ^staff}} = entry <- Timeline.flatten(score, ctx),
          do: {entry.kind, entry.start, Entry.end_tick(entry)}

    Spans.cursor(spans, at)
  end

  @doc """
  Inserts `ticks` of time at absolute tick `at` on one staff: every event on
  `staff` starting at or after `at` moves right by `ticks`, through the end
  of the piece. An event sounding across `at` is split there and its tail
  moves; the tie between a note's halves is dropped, since they no longer
  touch. Filler rests don't move: the gaps between moved events move with
  them, and trailing filler shrinks, so bars are appended only when notes
  or placed rests run past the last one. The other staff is untouched.
  """
  @spec insert_time(Score.t(), Context.t(), non_neg_integer(), pos_integer(), Note.staff()) ::
          Editing.result()
  def insert_time(%Score{} = score, %Context{} = ctx, at, ticks, staff)
      when is_integer(at) and at >= 0 and is_integer(ticks) and ticks > 0 do
    entries =
      score
      |> Timeline.flatten(ctx)
      |> Enum.reject(&Fillers.filler?/1)
      |> Enum.flat_map(fn
        %{event: %{staff: ^staff}} = entry when entry.start >= at ->
          [%{entry | start: entry.start + ticks}]

        %{event: %{staff: ^staff}} = entry when entry.start + entry.ticks > at ->
          split_at(entry, at, ticks)

        entry ->
          [entry]
      end)

    Rebuild.rebuild(score, ctx, Ties.merge(entries))
  end

  @doc """
  Re-reads a score written against `from_ctx` into the bars of `to_ctx`
  (after a time signature or pickup change): every event keeps its time
  from the start, events crossing the new bar lines are split into ties,
  and the score keeps at least as many bars as the music spanned.
  """
  @spec rebar_to(Score.t(), Context.t(), Context.t()) :: Editing.result()
  def rebar_to(%Score{} = score, %Context{} = from_ctx, %Context{} = to_ctx) do
    bars = bars_spanning(to_ctx, Timeline.end_tick(score, from_ctx))
    fresh = %{Score.new(bars) | tempos: score.tempos}
    Rebuild.rebuild(fresh, to_ctx, Ties.merge(Timeline.flatten(score, from_ctx)))
  end

  @doc "Removes the notes and rests with the given ids."
  @spec remove(Score.t(), Context.t(), [Editing.id()]) :: Editing.result()
  def remove(%Score{} = score, %Context{} = ctx, ids) do
    {_removed, kept} = Entry.select(Timeline.flatten(score, ctx), ids)
    Rebuild.rebuild(score, ctx, kept)
  end

  @doc """
  Plays the events backwards within the time they span. Ties inside the
  selection are flipped so they still point forward; ties into or out of
  it are dropped.
  """
  @spec reverse(Score.t(), Context.t(), [Editing.id()]) :: Editing.result()
  def reverse(%Score{} = score, %Context{} = ctx, ids) do
    ids = MapSet.new(ids)
    entries = Timeline.flatten(score, ctx)

    case Entry.select(entries, ids) do
      {[], _others} ->
        {:ok, score}

      {selected, _others} ->
        sum = Spans.mirror_sum(selected)
        flipped = Ties.flipped(selected, ids)
        Rebuild.rebuild(score, ctx, Enum.map(entries, &mirror(&1, ids, sum, flipped)))
    end
  end

  @doc """
  Ids of the events starting in ticks `from..to-1` on the given staves. A
  filler rest counts only when it also ends within the range, so a band
  over a few notes doesn't take in a bar-long rest on the other staff.
  """
  @spec select_range(Score.t(), Context.t(), integer(), integer(), [Note.staff()]) ::
          [Editing.id()]
  def select_range(%Score{} = score, %Context{} = ctx, from, to, staves) do
    for entry <- Timeline.flatten(score, ctx),
        entry.start >= from and entry.start < to,
        entry.event.staff in staves,
        not Fillers.filler?(entry) or Entry.end_tick(entry) <= to do
      entry.event.id
    end
  end

  @doc """
  Moves the given events `beats` time-signature units later (positive) or
  earlier. Events crossing a bar line are split into tied notes; measures
  are appended when needed.
  """
  @spec shift(Score.t(), Context.t(), [Editing.id()], integer()) :: Editing.result()
  def shift(%Score{} = score, %Context{} = ctx, ids, beats) when is_integer(beats) do
    delta = beats * Context.beat_ticks(ctx)

    with {:ok, entries} <-
           Rebuild.map_entries(score, ctx, ids, fn entry ->
             {:ok, %{entry | start: entry.start + delta, event: Fillers.claim(entry.event)}}
           end) do
      Rebuild.rebuild(score, ctx, Ties.merge(entries))
    end
  end

  @doc """
  Moves the rest `id` one item `:earlier` or `:later` on its staff and
  voice: it trades places with the note or rest beside it, which moves by
  the rest's length the other way. A rest is only silence, so the moved
  rest becomes filler again: the rebuild rewrites the gaps of every bar it
  touches as rests on the beats, and splits a note pushed over a bar line
  into tied notes. Returns the id of the rest now where the moved one
  starts, to keep it selected. Nothing beside it: nothing changes.
  """
  @spec step_rest(Score.t(), Context.t(), Editing.id(), :earlier | :later) ::
          {:ok, Score.t(), [Editing.id()]} | {:error, Editing.reason()}
  def step_rest(%Score{} = score, %Context{} = ctx, id, direction)
      when direction in [:earlier, :later] do
    entries = Timeline.flatten(score, ctx)

    with {:ok, %{kind: :rest} = rest} <- Entry.find(entries, id),
         %{} = other <- beside(entries, rest, direction) do
      {rest, other} = trade(rest, other, direction)
      moved = %{rest | event: %{rest.event | filler: true}}
      others = Enum.reject(entries, &(&1.event.id in [rest.event.id, other.event.id]))

      with {:ok, score} <- Rebuild.rebuild(score, ctx, Ties.merge([moved, other | others])) do
        {:ok, score, rest_at(score, ctx, moved)}
      end
    else
      {:ok, _note} -> {:error, :not_found}
      nil -> {:ok, score, [id]}
      {:error, _reason} = error -> error
    end
  end

  defp bars_after(first, last, _bar) when last <= first, do: 1
  defp bars_after(first, last, bar), do: 1 + div(last - first + bar - 1, bar)

  # How many bars of `ctx` it takes to reach tick `last` (at least one).
  defp bars_spanning(ctx, last) do
    bars_after(Context.capacity(ctx, 0), last, Context.measure_ticks(ctx))
  end

  # The item right before or after `rest` on its staff and voice, or nil.
  defp beside(entries, rest, direction) do
    %{staff: staff, voice: voice} = rest.event

    Enum.find(entries, fn entry ->
      entry.event.staff == staff and entry.event.voice == voice and
        touches?(entry, rest, direction)
    end)
  end

  defp mirror(entry, ids, sum, flipped) do
    if entry.event.id in ids do
      %{
        entry
        | start: sum - Entry.end_tick(entry),
          event: Ties.put(entry.event, flipped[entry.event.id])
      }
    else
      entry
    end
  end

  # The rest in the rebuilt score covering where `moved` now starts, on its
  # staff and voice (the refill may have joined it to a neighbour).
  defp rest_at(score, ctx, moved) do
    %{staff: staff, voice: voice} = moved.event

    for entry <- Timeline.flatten(score, ctx),
        entry.kind == :rest,
        entry.event.staff == staff and entry.event.voice == voice,
        entry.start <= moved.start and moved.start < Entry.end_tick(entry),
        do: entry.event.id
  end

  # Head up to `at` (keeping the id), tail moved `gap` later with a fresh id
  # and whatever tie the event had.
  defp split_at(entry, at, gap) do
    head = %{entry | ticks: at - entry.start, event: Ties.put(entry.event, nil)}

    tail = %{
      entry
      | start: at + gap,
        ticks: Entry.end_tick(entry) - at,
        event: %{entry.event | id: Ecto.UUID.generate()}
    }

    [head, tail]
  end

  # Whether `entry` ends where `rest` starts (:earlier) or starts where it
  # ends (:later).
  defp touches?(entry, rest, :earlier), do: Entry.end_tick(entry) == rest.start
  defp touches?(entry, rest, :later), do: entry.start == Entry.end_tick(rest)

  # The rest and its neighbour trade places in the time they share.
  defp trade(rest, other, :earlier) do
    {%{rest | start: other.start}, %{other | start: other.start + rest.ticks}}
  end

  defp trade(rest, other, :later) do
    {%{rest | start: rest.start + other.ticks}, %{other | start: rest.start}}
  end

  # An item sounding into cleared time from before `from` keeps its part
  # before it (untied); one starting inside it goes.
  defp trim_before(entry, from) when entry.start < from do
    [%{entry | ticks: from - entry.start, event: Ties.put(entry.event, nil)}]
  end

  defp trim_before(_entry, _from), do: []
end
