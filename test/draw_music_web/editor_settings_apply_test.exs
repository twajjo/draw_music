defmodule DrawMusicWeb.EditorSettingsApplyTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Music.{Context, Note, Score, Session}
  alias DrawMusicWeb.EditorSettings

  # A half and a quarter starting together in one voice: a score the bars
  # can't be re-flowed from (as older imports left them).
  defp clashing_session do
    notes = [
      %Note{id: Ecto.UUID.generate(), staff: :bass, offset: 0, value: :half, step: 15},
      %Note{id: Ecto.UUID.generate(), staff: :bass, offset: 0, value: :quarter, step: 21}
    ]

    [measure] = Score.new().measures
    Session.new(%Score{measures: [%{measure | notes: notes}]}, %Context{})
  end

  test "a new tempo leaves the score alone" do
    session = clashing_session()

    assert {:ok, changed} = EditorSettings.apply(session, %{tempo_bpm: 60})
    assert changed.ctx.tempo_bpm == 60
    assert changed.score == session.score
  end

  test "the tempo change can be undone" do
    {:ok, changed} = EditorSettings.apply(clashing_session(), %{tempo_bpm: 60})
    assert Session.undo(changed).ctx.tempo_bpm == %Context{}.tempo_bpm
  end

  test "a new time signature still re-flows the bars, and reports what blocks it" do
    assert {:error, :overlap} = EditorSettings.apply(clashing_session(), %{time_num: 3})
  end
end
