defmodule DrawMusic.Music.Spans do
  @moduledoc """
  Time spans on the score's absolute axis (ticks from the start, see
  `DrawMusic.Music.Timeline`): `{from, to}` with `to` excluded, or entries'
  `start` and `ticks`. Pure arithmetic for `DrawMusic.Music.Editing`.
  """

  alias DrawMusic.Music.Entry

  @type span :: {non_neg_integer(), non_neg_integer()}

  @doc """
  Where an insert at tick `at` lands among items `{kind, from, to}`, like a
  text cursor among characters: out of whatever item `at` falls inside, to
  a note's end or a rest's start (and on, if that's inside another).
  """
  @spec cursor([{:note | :rest, non_neg_integer(), non_neg_integer()}], non_neg_integer()) ::
          non_neg_integer()
  def cursor(items, at) do
    case Enum.find(items, fn {_kind, from, to} -> from < at and at < to end) do
      nil -> at
      {:note, _from, to} -> cursor(items, to)
      {_rest, from, _to} -> from
    end
  end

  @doc "Removes the time `cover` from each of `spans`."
  @spec cut_out(span(), [span()]) :: [span()]
  def cut_out({cover_from, cover_to}, spans) do
    Enum.flat_map(spans, fn {from, to} ->
      Enum.reject([{from, min(to, cover_from)}, {max(from, cover_to), to}], fn {a, b} ->
        a >= b
      end)
    end)
  end

  @doc """
  The time `removed` entries took, merged, less the time `kept` entries
  still cover: the gaps deleting them leaves.
  """
  @spec emptied([Entry.t()], [Entry.t()]) :: [span()]
  def emptied(removed, kept) do
    covers = Enum.map(kept, &of/1)

    removed
    |> Enum.map(&of/1)
    |> merge()
    |> Enum.flat_map(fn span -> Enum.reduce(covers, [span], &cut_out/2) end)
  end

  @doc "`spans` sorted, with overlapping or touching ones joined."
  @spec merge([span()]) :: [span()]
  def merge(spans) do
    spans
    |> Enum.sort()
    |> Enum.reduce([], fn
      {from, to}, [{prev_from, prev_to} | rest] when from <= prev_to ->
        [{prev_from, max(to, prev_to)} | rest]

      span, acc ->
        [span | acc]
    end)
    |> Enum.reverse()
  end

  @doc """
  The entries' first tick plus their last: playing them backwards, an item
  ending at `e` starts at `mirror_sum - e`.
  """
  @spec mirror_sum([Entry.t(), ...]) :: non_neg_integer()
  def mirror_sum(entries) do
    first = Enum.min_by(entries, & &1.start).start
    last = Enum.max(Enum.map(entries, &(&1.start + &1.ticks)))
    first + last
  end

  @doc "Whether two entries on one staff and voice sound at the same time."
  @spec overlapping_in_voice?(Entry.t(), Entry.t()) :: boolean()
  def overlapping_in_voice?(a, b) do
    a.event.staff == b.event.staff and a.event.voice == b.event.voice and
      a.start < b.start + b.ticks and b.start < a.start + a.ticks
  end

  defp of(entry), do: {entry.start, entry.start + entry.ticks}
end
