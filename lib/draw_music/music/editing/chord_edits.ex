defmodule DrawMusic.Music.Editing.ChordEdits do
  @moduledoc """
  Chord edits for `DrawMusic.Music.Editing` (whose moduledoc has the
  score's rules): finding a chord's notes, adding a note to a chord, and
  turning notes into chords. A chord is the notes of one staff and voice
  that start together (`DrawMusic.Music.Entry.chord_key/1`): in one voice
  they have the same length, or the edit was refused. (`DrawMusic.Music.Chords`
  works out chords' pitches; this edits them in the score.)
  """

  alias DrawMusic.Music.{Context, Editing, Entry, Pitch, Score, Timeline}
  alias DrawMusic.Music.Editing.Rebuild

  @typedoc "The pitches of the chord to build on a root `{step, alter}`, or why not."
  @type pitches_for ::
          (integer(), -2..2 -> {:ok, [{integer(), -2..2}]} | {:error, Editing.reason()})

  @doc """
  Adds a note to the chord `id` belongs to: `steps` scale steps above its
  top note (positive) or below its bottom note (negative), on the key's
  version of that letter. Returns the new note's id.
  """
  @spec add_to_chord(Score.t(), Context.t(), Editing.id(), integer()) ::
          {:ok, Score.t(), Editing.id()} | {:error, Editing.reason()}
  def add_to_chord(%Score{} = score, %Context{} = ctx, id, steps)
      when is_integer(steps) and steps != 0 do
    entries = Timeline.flatten(score, ctx)

    case Entry.find(entries, id) do
      {:ok, %{kind: :note} = entry} ->
        chord = Enum.filter(entries, &same_chord?(entry, &1))

        edge =
          if steps > 0,
            do: Enum.max_by(chord, & &1.event.step),
            else: Enum.min_by(chord, & &1.event.step)

        step = edge.event.step + steps

        note = %{
          edge.event
          | id: Ecto.UUID.generate(),
            step: step,
            alter: Pitch.in_key(step, ctx.sf),
            tie_to: nil
        }

        with {:ok, score} <- Rebuild.add(score, ctx, [%{edge | event: note}]),
             do: {:ok, score, note.id}

      {:ok, _rest} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  @doc """
  Ids of the chord `id` belongs to: the notes of its staff and voice that
  start and end with it (just `[id]` for a rest or a lone note).
  """
  @spec chord_ids(Score.t(), Context.t(), Editing.id()) :: [Editing.id()]
  def chord_ids(%Score{} = score, %Context{} = ctx, id) do
    entries = Timeline.flatten(score, ctx)

    case Entry.find(entries, id) do
      {:ok, %{kind: :note} = entry} ->
        for other <- entries, same_chord?(entry, other), do: other.event.id

      _rest_or_missing ->
        [id]
    end
  end

  @doc """
  Turns each note among `ids` into a chord: the whole chord it belongs to
  (its staff, voice and start) is replaced by the pitches `pitches_for`
  gives for that chord's lowest note, at the same time, length and voice.
  The lowest note keeps its id for the chord's first pitch; ties into or out
  of the replaced notes go. Returns the ids of every new chord's notes.
  """
  @spec chordify(Score.t(), Context.t(), [Editing.id()], pitches_for()) ::
          {:ok, Score.t(), [Editing.id()]} | {:error, Editing.reason()}
  def chordify(%Score{} = score, %Context{} = ctx, ids, pitches_for)
      when is_function(pitches_for, 2) do
    entries = Timeline.flatten(score, ctx)
    ids = MapSet.new(ids)

    chords =
      entries
      |> Enum.filter(&(&1.kind == :note and &1.event.id in ids))
      |> Enum.map(&Entry.chord_key/1)
      |> Enum.uniq()

    with {:ok, entries, new_ids} <- rebuild_chords(entries, chords, pitches_for),
         {:ok, score} <- Rebuild.rebuild(score, ctx, entries) do
      {:ok, score, new_ids}
    end
  end

  defp chord_entries(root, pitches) do
    pitches
    |> Enum.with_index()
    |> Enum.map(fn {{step, alter}, i} ->
      id = if i == 0, do: root.event.id, else: Ecto.UUID.generate()
      %{root | event: %{root.event | id: id, step: step, alter: alter, tie_to: nil}}
    end)
  end

  defp rebuild_chords(entries, chords, pitches_for) do
    Enum.reduce_while(chords, {:ok, entries, []}, fn key, {:ok, entries, new_ids} ->
      {old, kept} = Enum.split_with(entries, &(&1.kind == :note and Entry.chord_key(&1) == key))
      root = Enum.min_by(old, & &1.event.step)

      case pitches_for.(root.event.step, root.event.alter) do
        {:ok, pitches} ->
          chord = chord_entries(root, pitches)
          {:cont, {:ok, kept ++ chord, new_ids ++ Enum.map(chord, & &1.event.id)}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp same_chord?(%{kind: :note} = entry, %{kind: :note} = other) do
    Entry.chord_key(entry) == Entry.chord_key(other)
  end

  defp same_chord?(_entry, _other), do: false
end
