defmodule DrawMusic.Music.StaffCrossing do
  @moduledoc """
  Which staff a moved note belongs on, and moving it there.

  Middle C (step 28) is the boundary between the staves: a bass note moved
  above it belongs on the treble staff, a treble note moved below it on the
  bass staff, and middle C itself stays on whichever staff it is on.

  A note moved to the other staff keeps its time, length, dots and pitch.
  There it joins a note that starts and ends with it as a chord (in that
  note's voice), or else goes in the lowest voice where no note overlaps it;
  rests in that voice under it give way. These are plain functions over
  timeline entries (`DrawMusic.Music.Timeline.flatten/2`); `Editing`
  rebuilds the score from what they return.
  """

  alias DrawMusic.Music.{Entry, Note}

  @middle_c 28

  @doc """
  Moves the note `id` among `entries` to `staff` (nothing changes if it is
  already there). `{:error, :duplicate}` if the chord it would join already
  has its pitch; `{:error, :overlap}` if no voice has room for it.
  """
  @spec restaff([Entry.t()], Ecto.UUID.t(), Note.staff()) ::
          {:ok, [Entry.t()]} | {:error, :duplicate | :overlap}
  def restaff(entries, id, staff) do
    case Enum.split_with(entries, &(&1.event.id == id)) do
      {[%Entry{kind: :note, event: %{staff: ^staff}}], _others} -> {:ok, entries}
      {[%Entry{kind: :note} = moving], others} -> place_on(moving, others, staff)
      _not_a_note -> {:ok, entries}
    end
  end

  @doc """
  Moves each note among `ids` that has left its staff's side of middle C
  (`staff_for/2`) to the other staff, in turn, so the notes of a chord
  moved together stay together.
  """
  @spec settle([Entry.t()], [Ecto.UUID.t()]) ::
          {:ok, [Entry.t()]} | {:error, :duplicate | :overlap}
  def settle(entries, ids) do
    Enum.reduce_while(ids, {:ok, entries}, fn id, {:ok, entries} ->
      case crossing(entries, id) do
        nil -> {:cont, {:ok, entries}}
        staff -> entries |> restaff(id, staff) |> continue_if_ok()
      end
    end)
  end

  @doc "The staff a note on `staff` at `step` belongs on."
  @spec staff_for(Note.staff(), integer()) :: Note.staff()
  def staff_for(:bass, step) when step > @middle_c, do: :treble
  def staff_for(:treble, step) when step < @middle_c, do: :bass
  def staff_for(staff, _step), do: staff

  defp continue_if_ok({:ok, _entries} = ok), do: {:cont, ok}
  defp continue_if_ok(error), do: {:halt, error}

  # Where the note `id` should go, or nil when it stays.
  defp crossing(entries, id) do
    case Enum.find(entries, &(&1.event.id == id)) do
      %Entry{kind: :note, event: %{staff: staff, step: step}} -> other_staff(staff, step)
      _rest_or_missing -> nil
    end
  end

  # The lowest voice no note on the staff overlaps.
  defp free_voice(moving, on_staff) do
    taken =
      for %Entry{kind: :note} = note <- on_staff, overlap?(note, moving), do: note.event.voice

    case Enum.find(Note.voices(), &(&1 not in taken)) do
      nil -> {:error, :overlap}
      voice -> {:ok, voice}
    end
  end

  # The voice of the chord it joins, unless the chord already has its pitch.
  defp join(moving, [first | _] = chord) do
    case Enum.any?(chord, &(&1.event.step == moving.event.step)) do
      true -> {:error, :duplicate}
      false -> {:ok, first.event.voice}
    end
  end

  defp other_staff(staff, step) do
    case staff_for(staff, step) do
      ^staff -> nil
      other -> other
    end
  end

  defp overlap?(a, b), do: a.start < b.start + b.ticks and b.start < a.start + a.ticks

  defp place_on(moving, others, staff) do
    on_staff = Enum.filter(others, &(&1.event.staff == staff))

    with {:ok, voice} <- voice_for(moving, on_staff) do
      # A tie can't reach across staves; one into it goes when the score is
      # rebuilt.
      moved = %{moving | event: %{moving.event | staff: staff, voice: voice, tie_to: nil}}
      {:ok, [moved | Enum.reject(others, &rest_under?(&1, moved))]}
    end
  end

  defp rest_under?(%Entry{kind: :rest} = rest, moved) do
    rest.event.staff == moved.event.staff and rest.event.voice == moved.event.voice and
      overlap?(rest, moved)
  end

  defp rest_under?(_entry, _moved), do: false

  defp same_time?(%Entry{kind: :note, start: start, ticks: ticks}, %Entry{
         start: start,
         ticks: ticks
       }) do
    true
  end

  defp same_time?(_entry, _moving), do: false

  # A note starting and ending with it joins that chord; otherwise a voice
  # with room.
  defp voice_for(moving, on_staff) do
    case Enum.filter(on_staff, &same_time?(&1, moving)) do
      [] -> free_voice(moving, on_staff)
      chord -> join(moving, chord)
    end
  end
end
