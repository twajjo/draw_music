defmodule DrawMusic.Music.Stems do
  @moduledoc """
  Stem direction.

  When a staff has more than one voice in a measure, odd voices (1, 3) stem
  up and even voices (2, 4) stem down, keeping the lines apart. Otherwise
  stems go up when the notes lie mostly below the staff's middle line and
  down otherwise: for a chord or beamed group the note farthest from the
  middle line decides, and when the extremes are equally far, stems go down.
  """

  # Middle lines: B4 on the treble staff, D3 on the bass staff.
  @middle %{treble: 34, bass: 22}

  @doc "`:up` or `:down` for one voice's notes on `steps` of `staff`."
  @spec direction(Note.staff(), [integer(), ...]) :: :up | :down
  @spec direction(Note.staff(), [integer(), ...], pos_integer(), pos_integer()) :: :up | :down
  def direction(staff, steps) when is_list(steps) and steps != [] do
    middle = Map.fetch!(@middle, staff)
    above = Enum.max(steps) - middle
    below = middle - Enum.min(steps)

    if below > above, do: :up, else: :down
  end

  @doc """
  Like `direction/2`, for `voice` on a staff whose measure uses
  `voice_count` voices.
  """
  def direction(staff, steps, _voice, 1), do: direction(staff, steps)
  def direction(_staff, _steps, voice, _voice_count) when rem(voice, 2) == 1, do: :up
  def direction(_staff, _steps, _voice, _voice_count), do: :down
end
