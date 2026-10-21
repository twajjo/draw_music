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
  def displayed(%Measure{notes: notes}, sf, tied_in \\ MapSet.new()) do
    {shown, _in_effect} =
      notes
      |> Enum.sort_by(&{&1.offset, &1.step})
      |> Enum.reduce({%{}, %{}}, fn note, {shown, in_effect} ->
        position = {note.staff, note.step}
        current = Map.get(in_effect, position, Pitch.key_alter(sf, Pitch.letter(note.step)))

        cond do
          note.id in tied_in -> {shown, Map.put(in_effect, position, note.alter)}
          note.alter == current -> {shown, in_effect}
          true -> {Map.put(shown, note.id, note.alter), Map.put(in_effect, position, note.alter)}
        end
      end)

    shown
  end
end
