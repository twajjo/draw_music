defmodule DrawMusic.Music.Accidentals do
  @moduledoc """
  Decides which notes show an accidental (♯ ♭ ♮ 𝄪 𝄫).

  A sign shows only when a note's alteration differs from what is in effect
  at that point: the key signature, overridden by any earlier accidental on
  the same staff position, staff and measure. A natural therefore appears
  only when the note would otherwise read sharp or flat. A note continuing a
  tie from the previous measure shows no sign; it keeps the tied pitch.
  """

  alias DrawMusic.Music.{Measure, Pitch}

  @doc """
  Returns `%{note_id => alter}` for the notes of `measure` that show a sign.
  `tied_in` is the set of note ids that are tie targets from the previous
  measure.
  """
  @spec displayed(Measure.t(), -7..7) :: %{Ecto.UUID.t() => -2..2}
  @spec displayed(Measure.t(), -7..7, MapSet.t(Ecto.UUID.t())) :: %{Ecto.UUID.t() => -2..2}
  def displayed(%Measure{notes: notes}, sf, tied_in \\ MapSet.new()) do
    {shown, _in_effect} =
      notes
      |> Enum.sort_by(&{&1.offset, &1.step})
      |> Enum.reduce({%{}, %{}}, &mark(&1, &1.id in tied_in, sf, &2))

    shown
  end

  # `in_effect` is `%{{staff, step} => alter}` for positions altered so far.
  defp mark(note, true = _tied_in?, _sf, {shown, in_effect}) do
    {shown, Map.put(in_effect, {note.staff, note.step}, note.alter)}
  end

  defp mark(%{alter: alter} = note, false, sf, {shown, in_effect}) do
    position = {note.staff, note.step}

    case Map.get(in_effect, position, Pitch.key_alter(sf, Pitch.letter(note.step))) do
      ^alter -> {shown, in_effect}
      _other -> {Map.put(shown, note.id, alter), Map.put(in_effect, position, alter)}
    end
  end
end
