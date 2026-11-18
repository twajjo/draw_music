defmodule DrawMusic.Music.Editing.Pitches do
  @moduledoc """
  Pitch changes for `DrawMusic.Music.Editing` (whose moduledoc has the
  score's rules): alterations, moves up and down the key's scale, exact and
  chromatic transposition, and moves between the staves. A note taken past
  its staff's half of the gap between the staves moves to the other staff
  (`DrawMusic.Music.StaffCrossing`). Rests among the ids are left as they
  are.
  """

  alias DrawMusic.Music.{Context, Editing, Entry, Note, Pitch, Score, StaffCrossing, Timeline}
  alias DrawMusic.Music.Editing.Rebuild

  @doc """
  Moves the given notes `delta` steps up (positive) or down the scale of the
  key. Each keeps its accidental: the key's version of its new letter,
  sharpened or flattened as much as it was (F♯ up a step in C major is G♯;
  the key's own F♯ in G major goes to G).
  """
  @spec move_steps(Score.t(), Context.t(), [Editing.id()], integer()) :: Editing.result()
  def move_steps(%Score{} = score, %Context{} = ctx, ids, delta) when is_integer(delta) do
    move_pitches(score, ctx, ids, fn note ->
      step = note.step + delta
      %{note | step: step, alter: kept_alter(ctx.sf, note, step)}
    end)
  end

  @doc """
  Moves note `id` onto `step` of `staff` (where a single dragged note was
  let go), keeping its time, value, dots and accidental (as
  `move_steps/4`). On another staff it leaves its chord and voice, and
  joins a note there that starts and ends with it as a chord, or else goes
  in the lowest voice with room. Returns its id.
  """
  @spec move_to_staff(Score.t(), Context.t(), Editing.id(), Note.staff(), integer()) ::
          {:ok, Score.t(), Editing.id()} | {:error, Editing.reason()}
  def move_to_staff(%Score{} = score, %Context{} = ctx, id, staff, step) do
    entries = Timeline.flatten(score, ctx)

    case Entry.find(entries, id) do
      {:ok, %{kind: :note, event: note} = entry} ->
        moved = %{entry | event: %{note | step: step, alter: kept_alter(ctx.sf, note, step)}}

        with {:ok, entries} <-
               entries
               |> Entry.replace(id, [moved])
               |> StaffCrossing.restaff(id, StaffCrossing.staff_for(staff, step)),
             {:ok, score} <- Rebuild.rebuild(score, ctx, entries) do
          {:ok, score, id}
        end

      {:ok, _rest} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  @doc """
  Puts the notes among `ids` on `staff` at their own pitches, however far
  from it they are (a left-hand part written high on the bass staff, say).
  Each joins a note there that starts and ends with it as a chord, or else
  goes in the lowest voice with room.
  """
  @spec put_on_staff(Score.t(), Context.t(), [Editing.id()], Note.staff()) :: Editing.result()
  def put_on_staff(%Score{} = score, %Context{} = ctx, ids, staff) do
    with {:ok, entries} <- StaffCrossing.restaff_all(Timeline.flatten(score, ctx), ids, staff) do
      Rebuild.rebuild(score, ctx, entries)
    end
  end

  @doc "Sets the absolute alteration (-2..2) of the given notes."
  @spec set_alter(Score.t(), Context.t(), [Editing.id()], -2..2) :: Editing.result()
  def set_alter(%Score{} = score, %Context{} = ctx, ids, alter) when alter in -2..2 do
    Rebuild.map_selected(score, ctx, ids, &note_only(&1, fn note -> %{note | alter: alter} end))
  end

  @doc "Moves notes by `semitones`, spelled to suit the key."
  @spec transpose_chromatic(Score.t(), Context.t(), [Editing.id()], integer()) ::
          Editing.result()
  def transpose_chromatic(%Score{} = score, %Context{} = ctx, ids, semitones)
      when is_integer(semitones) do
    move_pitches(score, ctx, ids, fn note ->
      {step, alter} = Pitch.spell(Note.midi(note) + semitones, ctx.sf)
      %{note | step: step, alter: alter}
    end)
  end

  @doc """
  Moves notes by an exact interval: the letter moves `steps` and the
  alteration makes up `semitones` (a major third up is 2 steps, 4
  semitones). A spelling needing more than a double sharp or flat is
  re-spelled for the key.
  """
  @spec transpose_interval(Score.t(), Context.t(), [Editing.id()], integer(), integer()) ::
          Editing.result()
  def transpose_interval(%Score{} = score, %Context{} = ctx, ids, steps, semitones)
      when is_integer(steps) and is_integer(semitones) do
    move_pitches(score, ctx, ids, fn note ->
      {step, alter} = Pitch.transpose(note.step, note.alter, steps, semitones, ctx.sf)
      %{note | step: step, alter: alter}
    end)
  end

  # A moved note's new alteration: the key's version of letter `step`,
  # sharpened or flattened as much as the note was from its own key letter.
  defp kept_alter(sf, note, step) do
    accidental = note.alter - Pitch.in_key(note.step, sf)

    (Pitch.in_key(step, sf) + accidental)
    |> max(-2)
    |> min(2)
  end

  # Changes the pitch of the notes among `ids` (`fun`, note to note); any
  # taken past their staff's half of the gap move to the other staff.
  defp move_pitches(score, ctx, ids, fun) do
    with {:ok, entries} <- Rebuild.map_entries(score, ctx, ids, &note_only(&1, fun)),
         {:ok, entries} <- StaffCrossing.settle(entries, ids) do
      Rebuild.rebuild(score, ctx, entries)
    end
  end

  defp note_only(%{kind: :note} = entry, fun), do: {:ok, %{entry | event: fun.(entry.event)}}
  defp note_only(entry, _fun), do: {:ok, entry}
end
