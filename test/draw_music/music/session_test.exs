defmodule DrawMusic.Music.SessionTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Music.{Context, Editing, Score, Session}

  @ctx %Context{}

  defp place(session, spn, offset) do
    {step, alter} = pitch!(spn)

    Session.edit(session, fn score, ctx ->
      Editing.place_note(score, ctx, 0, %{
        staff: :treble,
        offset: offset,
        value: :quarter,
        step: step,
        alter: alter
      })
    end)
  end

  setup do
    %{session: Session.new(Score.new(), @ctx)}
  end

  test "a score with no measures starts with one empty bar" do
    assert [_one] = Session.new(%Score{measures: []}, @ctx).score.measures
  end

  test "an edit can be undone and redone", %{session: session} do
    {:ok, edited, id} = place(session, "C4", 0)

    undone = Session.undo(edited)
    assert notes(undone.score) == []

    redone = Session.redo(undone)
    assert [{0, 0, "C4", :quarter, 0}] = notes(redone.score)
    assert MapSet.member?(Session.event_ids(redone), id)
  end

  test "an edit that changes nothing isn't recorded", %{session: session} do
    {:ok, edited, _id} = place(session, "C4", 0)
    saved = Session.saved(Session.undo(edited) |> Session.redo())

    assert {:ok, same, nil} = Session.edit(saved, fn score, _ctx -> {:ok, score} end)
    refute same.dirty?
    assert same.undo == saved.undo
    assert same.redo == saved.redo
  end

  test "a new edit clears the redo history", %{session: session} do
    {:ok, edited, _id} = place(session, "C4", 0)
    undone = Session.undo(edited)
    {:ok, other, _id} = place(undone, "E4", 960)

    assert Session.redo(other) == other
  end

  test "undo and redo with nothing to do change nothing", %{session: session} do
    assert Session.undo(session) == session
    assert Session.redo(session) == session
  end

  test "a failed edit leaves the session unchanged", %{session: session} do
    assert place(session, "C4", 3840) == {:error, :measure_full}
  end

  test "edits mark the session dirty; saving clears it; undo after saving dirties it again",
       %{session: session} do
    refute session.dirty?
    {:ok, edited, _id} = place(session, "C4", 0)
    assert edited.dirty?

    saved = Session.saved(edited)
    refute saved.dirty?

    assert Session.undo(saved).dirty?
  end

  test "selection ignores unknown ids and drops ids that undo removed", %{session: session} do
    {:ok, edited, id} = place(session, "C4", 0)

    selected = Session.select(edited, [id, Ecto.UUID.generate()], false)
    assert selected.selection == MapSet.new([id])

    assert Session.undo(selected).selection == MapSet.new()
  end

  test "toggle adds and removes; select with add? keeps the existing selection",
       %{session: session} do
    {:ok, s, a} = place(session, "C4", 0)
    {:ok, s, b} = place(s, "E4", 960)

    s = Session.toggle(s, a)
    assert s.selection == MapSet.new([a])
    s = Session.select(s, [b], true)
    assert s.selection == MapSet.new([a, b])
    s = Session.toggle(s, a)
    assert s.selection == MapSet.new([b])
    assert Session.clear_selection(s).selection == MapSet.new()
  end

  test "a context change is undoable", %{session: session} do
    {:ok, s, _id} = place(session, "C4", 0)
    three_four = %Context{time_num: 3, time_den: 4}
    {:ok, rebarred} = Editing.rebar_to(s.score, s.ctx, three_four)

    changed = Session.change_context(s, three_four, rebarred)
    assert changed.ctx == three_four
    assert changed.dirty?

    assert Session.undo(changed).ctx == @ctx
  end
end
