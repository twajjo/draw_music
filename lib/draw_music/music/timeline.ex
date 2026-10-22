defmodule DrawMusic.Music.Timeline do
  @moduledoc """
  The score laid out on one absolute time axis (ticks from the start of the
  piece), and back again into measures.

  Notes and rests on that axis are `DrawMusic.Music.Entry` structs. Edits
  work on entries, then `rebar/3` re-flows them into measures: an entry
  crossing a bar line is split into tied notes (or consecutive rests), and
  measures are appended when the music runs past the last one.
  """

  alias DrawMusic.Music.{Context, Duration, Entry, Measure, Note, Rest, Score}

  @typedoc "A measure's first tick and length in ticks."
  @type bar :: {non_neg_integer(), pos_integer()}

  @doc "`{start, capacity}` of each measure."
  @spec bars(Score.t() | non_neg_integer(), Context.t()) :: [bar()]
  def bars(%Score{measures: measures}, ctx), do: bars(length(measures), ctx)

  def bars(count, %Context{} = ctx) when is_integer(count) do
    {bars, _end} =
      Enum.map_reduce(Enum.to_list(0..(count - 1)//1), 0, fn index, start ->
        capacity = Context.capacity(ctx, index)
        {{start, capacity}, start + capacity}
      end)

    bars
  end

  @doc "Tick at which the score ends."
  @spec end_tick(Score.t(), Context.t()) :: non_neg_integer()
  def end_tick(%Score{measures: measures}, ctx), do: Context.span(ctx, length(measures))

  @doc "All notes and rests as entries, in measure order."
  @spec flatten(Score.t(), Context.t()) :: [Entry.t()]
  def flatten(%Score{measures: measures} = score, ctx) do
    score
    |> bars(ctx)
    |> Enum.zip(measures)
    |> Enum.flat_map(fn {{start, _capacity}, measure} ->
      Enum.map(measure.notes, &entry(&1, start)) ++ Enum.map(measure.rests, &entry(&1, start))
    end)
  end

  @doc "Entry for an event placed in a measure starting at `bar_start`."
  @spec entry(Note.t() | Rest.t(), non_neg_integer()) :: Entry.t()
  def entry(%Note{} = note, bar_start),
    do: %Entry{kind: :note, start: bar_start + note.offset, ticks: Note.ticks(note), event: note}

  def entry(%Rest{} = rest, bar_start),
    do: %Entry{kind: :rest, start: bar_start + rest.offset, ticks: Rest.ticks(rest), event: rest}

  @doc """
  Re-flows entries into the score's measures (keeping measure ids and count,
  appending measures as needed). An entry keeps its value and dots when it
  fits in one bar; otherwise its length is split at bar lines and into note
  values, the pieces tied together. The first piece keeps the entry's id.
  """
  @spec rebar(Score.t(), Context.t(), [Entry.t()]) ::
          {:ok, Score.t()} | {:error, :before_start | :unrepresentable}
  def rebar(%Score{} = score, %Context{} = ctx, entries) do
    with :ok <- check_starts(entries) do
      last = entries |> Enum.map(&(&1.start + &1.ticks)) |> Enum.max(fn -> 0 end)
      measures = grow(score.measures, ctx, last)
      bars = measures |> length() |> bars(ctx) |> Enum.with_index()

      with {:ok, pieces} <- pieces(entries, bars) do
        {:ok, %{score | measures: assemble(measures, pieces)}}
      end
    end
  end

  defp check_starts(entries) do
    if Enum.any?(entries, &(&1.start < 0)), do: {:error, :before_start}, else: :ok
  end

  defp grow(measures, ctx, last) do
    if Context.span(ctx, length(measures)) >= last,
      do: measures,
      else: grow(measures ++ [Measure.new()], ctx, last)
  end

  defp pieces(entries, bars) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      case entry_pieces(entry, bars) do
        {:ok, pieces} -> {:cont, {:ok, pieces ++ acc}}
        error -> {:halt, error}
      end
    end)
  end

  defp entry_pieces(entry, bars) do
    case segments(entry.start, entry.ticks, bars) do
      [{index, offset, len}] when len == entry.ticks ->
        if keeps_value?(entry),
          do: {:ok, [{index, %{entry.event | offset: offset}}]},
          else: split(entry, [{index, offset, len}])

      segments ->
        split(entry, segments)
    end
  end

  defp keeps_value?(%{event: %{value: value, dots: dots}, ticks: ticks}) when not is_nil(value),
    do: Duration.ticks(value, dots) == ticks

  defp keeps_value?(_entry), do: false

  defp segments(_start, 0, _bars), do: []

  defp segments(start, ticks, bars) do
    {{bar_start, capacity}, index} =
      Enum.find(bars, fn {{bs, cap}, _i} -> start >= bs and start < bs + cap end)

    len = min(ticks, bar_start + capacity - start)
    [{index, start - bar_start, len} | segments(start + len, ticks - len, bars)]
  end

  defp split(entry, segments) do
    with {:ok, parts} <- decompose(segments) do
      {:ok, build(entry, parts)}
    end
  end

  # [{index, offset, len}] -> {:ok, [{index, offset, value, dots}]}
  defp decompose(segments) do
    Enum.reduce_while(segments, {:ok, []}, fn {index, offset, len}, {:ok, acc} ->
      case Duration.decompose(len) do
        {:ok, values} -> {:cont, {:ok, acc ++ place_values(index, offset, values)}}
        error -> {:halt, error}
      end
    end)
  end

  defp place_values(index, offset, values) do
    {parts, _end} =
      Enum.map_reduce(values, offset, fn {value, dots}, at ->
        {{index, at, value, dots}, at + Duration.ticks(value, dots)}
      end)

    parts
  end

  defp build(%{event: %Note{} = note}, parts) do
    ids = [
      note.id || Ecto.UUID.generate() | Enum.map(tl(parts), fn _ -> Ecto.UUID.generate() end)
    ]

    next_ids = tl(ids) ++ [note.tie_to]

    for {{index, offset, value, dots}, id, next} <- Enum.zip([parts, ids, next_ids]) do
      {index, %{note | id: id, offset: offset, value: value, dots: dots, tie_to: next}}
    end
  end

  defp build(%{event: %Rest{} = rest}, parts) do
    ids = [
      rest.id || Ecto.UUID.generate() | Enum.map(tl(parts), fn _ -> Ecto.UUID.generate() end)
    ]

    for {{index, offset, value, dots}, id} <- Enum.zip(parts, ids) do
      {index, %{rest | id: id, offset: offset, value: value, dots: dots}}
    end
  end

  defp assemble(measures, pieces) do
    by_index = Enum.group_by(pieces, &elem(&1, 0), &elem(&1, 1))

    measures
    |> Enum.with_index()
    |> Enum.map(fn {measure, index} ->
      events = Map.get(by_index, index, [])

      %{
        measure
        | notes:
            events
            |> Enum.filter(&match?(%Note{}, &1))
            |> Enum.sort_by(&{&1.offset, &1.staff, &1.voice, &1.step}),
          rests:
            events
            |> Enum.filter(&match?(%Rest{}, &1))
            |> Enum.sort_by(&{&1.offset, &1.staff, &1.voice})
      }
    end)
  end
end
