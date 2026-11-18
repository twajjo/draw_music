defmodule DrawMusic.Music.Editing.Values do
  @moduledoc """
  Length changes for `DrawMusic.Music.Editing` (whose moduledoc has the
  score's rules): dots, a new value, splitting in two, and turning a note
  into a rest or back, each in place. Whatever changes must still fit in
  its bar (`:measure_full`) and its voice (`:overlap`); give a chord's ids
  (`Editing.chord_ids/3`) to change it together. An edited rest is the
  user's, no longer rewritten as filler.
  """

  alias DrawMusic.Music.{
    Context,
    Duration,
    Editing,
    Entry,
    Fillers,
    Note,
    Rest,
    Score,
    Ties,
    Timeline
  }

  alias DrawMusic.Music.Editing.Rebuild

  @values Duration.values()

  @doc """
  Sets the dots of the given events. Each value must take that many dots
  (`:unrepresentable`: a 256th none, a 128th one).
  """
  @spec set_dots(Score.t(), Context.t(), [Editing.id()], 0..2) :: Editing.result()
  def set_dots(%Score{} = score, %Context{} = ctx, ids, dots) when dots in 0..2 do
    bars = Timeline.bars(score, ctx)

    Rebuild.map_selected(score, ctx, ids, fn entry ->
      with :ok <-
             Rebuild.ensure(Duration.dots_allowed?(entry.event.value, dots), :unrepresentable),
           ticks = Duration.ticks(entry.event.value, dots),
           :ok <- fits_bar(bars, entry.start, ticks) do
        {:ok, %{entry | ticks: ticks, event: Fillers.claim(%{entry.event | dots: dots})}}
      end
    end)
  end

  @doc "Changes the length of a note or rest (or a whole chord, given its ids) in place."
  @spec set_value(Score.t(), Context.t(), [Editing.id()], Duration.value(), 0..2) ::
          Editing.result()
  def set_value(_score, _ctx, _ids, value, _dots) when value not in @values do
    {:error, :unrepresentable}
  end

  def set_value(%Score{} = score, %Context{} = ctx, ids, value, dots) when dots in 0..2 do
    entries = Timeline.flatten(score, ctx)

    with :ok <- Rebuild.ensure(Duration.dots_allowed?(value, dots), :unrepresentable),
         ticks = Duration.ticks(value, dots),
         {:ok, [first | _] = chosen} <- Entry.find_all(entries, ids),
         :ok <- fits_bar(Timeline.bars(score, ctx), first.start, ticks) do
      changed =
        Map.new(chosen, fn entry ->
          {entry.event.id,
           %{
             entry
             | ticks: ticks,
               event: Fillers.claim(%{entry.event | value: value, dots: dots})
           }}
        end)

      Rebuild.rebuild(score, ctx, Enum.map(entries, &Map.get(changed, &1.event.id, &1)))
    end
  end

  @doc """
  Splits a note or rest into two. An undotted value becomes two of the next
  shorter value; a dotted one becomes the same value with one dot fewer plus
  the remainder (dotted quarter → quarter + eighth). A note's halves are tied.
  Returns the ids of the halves, head then tail for each event; heads keep
  the events' ids.
  """
  @spec split(Score.t(), Context.t(), [Editing.id()]) ::
          {:ok, Score.t(), [Editing.id()]} | {:error, Editing.reason()}
  def split(%Score{} = score, %Context{} = ctx, ids) when is_list(ids) do
    entries = Timeline.flatten(score, ctx)

    with {:ok, [first | _] = chosen} <- Entry.find_all(entries, ids),
         {:ok, head, tail} <- halves(first.event.value, first.event.dots),
         pieces = Map.new(chosen, &{&1.event.id, split_entry(&1, head, tail)}),
         {:ok, score} <-
           Rebuild.rebuild(
             score,
             ctx,
             Enum.flat_map(entries, &Map.get(pieces, &1.event.id, [&1]))
           ) do
      {:ok, score, for(entry <- chosen, piece <- pieces[entry.event.id], do: piece.event.id)}
    end
  end

  @doc """
  Turns a rest into a note of the same length and position (keeping its
  id), on `step` with `alter`.
  """
  @spec to_note(Score.t(), Context.t(), Editing.id(), integer(), -2..2) ::
          {:ok, Score.t(), Editing.id()} | {:error, Editing.reason()}
  def to_note(%Score{} = score, %Context{} = ctx, id, step, alter) when alter in -2..2 do
    entries = Timeline.flatten(score, ctx)

    with {:ok, entry} <- Entry.find(entries, id),
         note = Note.from(entry.event, id: id, step: step, alter: alter),
         note_entry = %{entry | kind: :note, event: note},
         {:ok, score} <- Rebuild.rebuild(score, ctx, Entry.replace(entries, id, [note_entry])) do
      {:ok, score, id}
    end
  end

  @doc """
  Turns a note (or a whole chord, given its ids) into one rest of the same
  length and position, keeping the first note's id; ties into or out of it
  are removed.
  """
  @spec to_rest(Score.t(), Context.t(), [Editing.id()]) ::
          {:ok, Score.t(), Editing.id()} | {:error, Editing.reason()}
  def to_rest(%Score{} = score, %Context{} = ctx, ids) when is_list(ids) do
    entries = Timeline.flatten(score, ctx)

    with {:ok, [%{event: %{id: first_id}} = first | _]} <- Entry.find_all(entries, ids),
         rest = Rest.from(first.event, id: first_id),
         {_others, kept} = Entry.select(entries, List.delete(ids, first_id)),
         replaced = Entry.replace(kept, first_id, [%{first | kind: :rest, event: rest}]),
         {:ok, score} <- Rebuild.rebuild(score, ctx, replaced) do
      {:ok, score, first_id}
    end
  end

  # A new length for what starts at `start` must still end in its bar.
  defp fits_bar(bars, start, ticks) do
    Rebuild.ensure(Timeline.fits?(Timeline.bar_at(bars, start), start, ticks), :measure_full)
  end

  defp halves(value, 0) do
    case Enum.drop_while(@values, &(&1 != value)) do
      [_value, shorter | _] -> {:ok, {shorter, 0}, {shorter, 0}}
      _shortest -> {:error, :unrepresentable}
    end
  end

  defp halves(value, dots) do
    remainder = Duration.ticks(value, dots) - Duration.ticks(value, dots - 1)

    case Duration.decompose(remainder) do
      {:ok, [tail]} -> {:ok, {value, dots - 1}, tail}
      _ -> {:error, :unrepresentable}
    end
  end

  defp split_entry(entry, {head_value, head_dots}, {tail_value, tail_dots}) do
    second = Ecto.UUID.generate()
    head_ticks = Duration.ticks(head_value, head_dots)

    event = Fillers.claim(entry.event)

    head = %{
      entry
      | ticks: head_ticks,
        event: Ties.put(%{event | value: head_value, dots: head_dots}, second)
    }

    tail = %{
      entry
      | start: entry.start + head_ticks,
        ticks: entry.ticks - head_ticks,
        event: %{event | id: second, value: tail_value, dots: tail_dots}
    }

    [head, tail]
  end
end
