defmodule DrawMusicWeb.Editor.Messages do
  @moduledoc """
  What the editor tells the user when an edit is refused, by the reason
  `DrawMusic.Music.Editing` (or a tempo or menu action) gives.
  """

  @messages %{
    measure_full: "That bar is full",
    overlap: "Something is already there",
    duplicate: "That note is already there",
    out_of_range: "That would go outside the piano's range",
    not_tieable: "Only touching notes of the same pitch can be tied",
    last_measure: "A score needs at least one bar",
    unrepresentable: "That length can't be written as one note",
    no_such_measure: "That bar no longer exists",
    before_start: "That would move before the start",
    not_found: "That note no longer exists",
    pickup_bar: "Remove the pickup in the score settings first",
    past_end: "That's past the end of the score",
    invalid_tempo: "A rit. or accel. has to end after it starts",
    same_tempo: "A rit. or accel. has to reach a different tempo",
    opening_beat: "The opening tempo is set in Score settings"
  }

  @doc "What to tell the user when an edit is refused for `reason`."
  @spec refused(atom()) :: String.t()
  def refused(reason), do: Map.get(@messages, reason, "That can't be done here")
end
