defmodule DrawMusic.Music.Transpose do
  @moduledoc """
  Moves a whole score from one key to another, tonic to tonic. Letters move
  by the distance between the tonics and pitches by the matching number of
  semitones, so notes in the old key land in the new key and chromatic
  notes keep their relationship to it.
  """

  alias DrawMusic.Music.{Note, Pitch, Score}

  @doc """
  Transposes `score` from key `{sf, mode}` to key `{sf, mode}`. `direction`
  is `:nearest` (the smaller move, up on a tritone), `:up` or `:down`.
  Returns `{:error, :out_of_range}` if a note would leave A0–C8.
  """
  def to_key(%Score{} = score, {from_sf, from_mode}, {to_sf, to_mode}, direction \\ :nearest) do
    {from_letter, from_pc} = Pitch.tonic(from_sf, from_mode)
    {to_letter, to_pc} = Pitch.tonic(to_sf, to_mode)

    {steps, semis} =
      interval(
        Integer.mod(to_letter - from_letter, 7),
        Integer.mod(to_pc - from_pc, 12),
        direction
      )

    measures =
      Enum.map(score.measures, fn m ->
        %{m | notes: Enum.map(m.notes, &move(&1, steps, semis, to_sf))}
      end)

    if Enum.all?(measures, fn m -> Enum.all?(m.notes, &Pitch.in_range?(Note.midi(&1))) end),
      do: {:ok, %{score | measures: measures}},
      else: {:error, :out_of_range}
  end

  defp interval(steps_up, semis_up, :up), do: {steps_up, semis_up}
  defp interval(0, 0, :down), do: {0, 0}
  defp interval(steps_up, semis_up, :down), do: {steps_up - 7, semis_up - 12}

  defp interval(steps_up, semis_up, :nearest) when semis_up <= 6,
    do: interval(steps_up, semis_up, :up)

  defp interval(steps_up, semis_up, :nearest), do: interval(steps_up, semis_up, :down)

  defp move(%Note{} = note, steps, semis, to_sf) do
    midi = Note.midi(note) + semis
    step = note.step + steps
    alter = midi - Pitch.natural_midi(step)

    if alter in -2..2 do
      %{note | step: step, alter: alter}
    else
      {step, alter} = Pitch.spell(midi, to_sf)
      %{note | step: step, alter: alter}
    end
  end
end
