defmodule DrawMusic.Music.Ties do
  @moduledoc """
  Ties: a note's `tie_to` joins it to the same pitch starting exactly where
  it ends, on the same staff. `tie/4` and `untie/2` are edits (through
  `DrawMusic.Music.Editing`); the rest keep ties true as other edits move,
  copy, reverse and re-bar notes.
  """

  alias DrawMusic.Music.{Context, Entry, Note, Score, Timeline}

  @type id :: Ecto.UUID.t()

  @doc """
  The notes among `ids`, copied without them: a tie to a note left behind
  is dropped.
  """
  @spec drop_outside(Note.t() | struct(), MapSet.t(id())) :: Note.t() | struct()
  def drop_outside(%Note{tie_to: target} = note, ids) when not is_nil(target) do
    if target in ids, do: note, else: %{note | tie_to: nil}
  end

  def drop_outside(event, _ids), do: event

  @doc """
  For notes played backwards: each selected tie target mapped to the note
  tied to it, so the tie can be turned round to point forward again.
  """
  @spec flipped([Entry.t()], MapSet.t(id())) :: %{id() => id()}
  def flipped(selected, ids) do
    for %{event: %Note{id: from, tie_to: to}} <- selected, to in ids, into: %{}, do: {to, from}
  end

  @doc """
  Tied pieces of a lone note (no chord partner in its voice) that follow
  one another become one entry, keeping the first piece's id; re-barring
  splits it again only where bar lines and note values need it.
  """
  @spec merge([Entry.t()]) :: [Entry.t()]
  def merge(entries) do
    notes = for %{kind: :note} = entry <- entries, into: %{}, do: {entry.event.id, entry}
    sizes = notes |> Map.values() |> Enum.frequencies_by(&Entry.chord_key/1)

    lone? = fn entry ->
      sizes[Entry.chord_key(entry)] == 1
    end

    links =
      notes
      |> Map.values()
      |> Enum.flat_map(fn entry ->
        case Map.get(notes, entry.event.tie_to) do
          nil -> []
          target -> mergeable(entry, target, lone?)
        end
      end)
      |> Map.new()

    absorbed = MapSet.new(Map.values(links), & &1.event.id)

    entries
    |> Enum.reject(&(&1.event.id in absorbed))
    |> Enum.map(&extend(&1, links))
  end

  @doc "Drops ties that no longer join a note to the same pitch right after it."
  @spec prune(Score.t(), Context.t()) :: Score.t()
  def prune(%Score{} = score, %Context{} = ctx) do
    notes = note_entries(score, ctx)

    update_notes(score, fn
      %Note{tie_to: nil} = note -> note
      note -> keep_tie(note, notes[note.id], Map.get(notes, note.tie_to))
    end)
  end

  @doc "A note tied to `target` (nil: untied); any other event as it is."
  @spec put(Note.t() | struct(), id() | nil) :: Note.t() | struct()
  def put(%Note{} = note, target), do: %{note | tie_to: target}
  def put(event, _target), do: event

  @doc "A pasted note's tie, to its target's new id in `fresh` (old id => new)."
  @spec renumber(Note.t() | struct(), %{id() => id()}) :: Note.t() | struct()
  def renumber(%Note{tie_to: target} = note, fresh) when not is_nil(target) do
    %{note | tie_to: fresh[target]}
  end

  def renumber(event, _fresh), do: event

  @doc """
  Ties two notes, given in either order: the earlier is tied to the later.
  They must be on the same staff, sound the same pitch, and the later must
  start exactly where the earlier ends.
  """
  @spec tie(Score.t(), Context.t(), id(), id()) :: {:ok, Score.t()} | {:error, atom()}
  def tie(%Score{} = score, %Context{} = ctx, id_a, id_b) do
    notes = note_entries(score, ctx)

    with {:ok, a} <- fetch(notes, id_a),
         {:ok, b} <- fetch(notes, id_b),
         [first, second] = Enum.sort_by([a, b], & &1.start),
         :ok <- check_tieable(first, second) do
      {:ok, update_notes(score, &tie_note(&1, first.event.id, second.event.id))}
    end
  end

  @doc """
  Whether `first` can be tied to `second`: distinct notes on one staff, the
  same pitch, the second starting where the first ends.
  """
  @spec tieable?(Entry.t(), Entry.t()) :: boolean()
  def tieable?(%{event: %{id: id}}, %{event: %{id: id}}), do: false

  def tieable?(%{event: %{staff: staff}} = first, %{event: %{staff: staff}} = second) do
    Note.midi(first.event) == Note.midi(second.event) and
      Entry.end_tick(first) == second.start
  end

  def tieable?(_first, _second), do: false

  @doc "Removes the ties into and out of a note."
  @spec untie(Score.t(), id()) :: Score.t()
  def untie(%Score{} = score, id) do
    update_notes(score, fn
      %Note{id: ^id} = note -> %{note | tie_to: nil}
      %Note{tie_to: ^id} = note -> %{note | tie_to: nil}
      note -> note
    end)
  end

  defp check_tieable(first, second) do
    if tieable?(first, second), do: :ok, else: {:error, :not_tieable}
  end

  defp extend(entry, links) do
    case Map.get(links, entry.event.id) do
      nil ->
        entry

      next ->
        merged = extend(next, links)

        %{
          entry
          | ticks: entry.ticks + merged.ticks,
            event: put(entry.event, merged.event.tie_to)
        }
    end
  end

  defp fetch(notes, id) do
    case Map.fetch(notes, id) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, :not_found}
    end
  end

  defp keep_tie(note, _entry, nil = _target), do: %{note | tie_to: nil}

  defp keep_tie(note, entry, target) do
    if tieable?(entry, target), do: note, else: %{note | tie_to: nil}
  end

  defp mergeable(entry, target, lone?) do
    if entry.event.voice == target.event.voice and lone?.(entry) and lone?.(target) and
         tieable?(entry, target) do
      [{entry.event.id, target}]
    else
      []
    end
  end

  defp note_entries(score, ctx) do
    for %{kind: :note} = entry <- Timeline.flatten(score, ctx), into: %{} do
      {entry.event.id, entry}
    end
  end

  defp tie_note(%Note{id: id} = note, id, target), do: %{note | tie_to: target}
  defp tie_note(note, _id, _target), do: note

  defp update_notes(%Score{measures: measures} = score, fun) do
    %{score | measures: Enum.map(measures, fn m -> %{m | notes: Enum.map(m.notes, fun)} end)}
  end
end
