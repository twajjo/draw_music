defmodule DrawMusic.MusicHelpers do
  @moduledoc """
  Helpers for building scores in tests. Pitches are written in scientific
  pitch notation, e.g. `"F#4"`.
  """

  alias DrawMusic.Music.{Editing, Pitch, Timeline}

  def pitch!(spn) do
    {:ok, pitch} = Pitch.parse(spn)
    pitch
  end

  @doc "Places a note and returns `{score, id}`."
  def note!(score, ctx, index, spn, attrs) do
    {step, alter} = pitch!(spn)

    {:ok, score, id} =
      Editing.place_note(score, ctx, index, Map.merge(%{step: step, alter: alter}, attrs))

    {score, id}
  end

  @doc "All notes as `{measure_index, offset, spn, value, dots}`, in order."
  def notes(score) do
    for {measure, index} <- Enum.with_index(score.measures),
        note <- measure.notes,
        do: {index, note.offset, Pitch.name(note.step, note.alter), note.value, note.dots}
  end

  @doc "Ids of the notes of a tie chain starting at `id`."
  def tie_chain(score, id) do
    by_id = for m <- score.measures, n <- m.notes, into: %{}, do: {n.id, n}

    Stream.unfold(id, fn
      nil -> nil
      id -> {id, by_id[id].tie_to}
    end)
    |> Enum.to_list()
  end

  def entries(score, ctx), do: Timeline.flatten(score, ctx)
end
