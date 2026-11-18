defmodule DrawMusic.Music.SessionTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Music.{Context, Editing, Score, Session, Timeline}

  @ctx %Context{}

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

  test "collapse_selection keeps only the earliest selected event", %{session: session} do
    {:ok, s, late} = place(session, "G4", 1920)
    {:ok, s, early} = place(s, "C4", 0)
    {:ok, s, middle} = place(s, "E4", 960)

    collapsed = s |> Session.select([late, middle, early], false) |> Session.collapse_selection()
    assert collapsed.selection == MapSet.new([early])

    assert Session.collapse_selection(s).selection == MapSet.new()
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

  test "copy fills the clipboard from the selection; with none, nothing changes",
       %{session: session} do
    {:ok, s, id} = place(session, "C4", 0)

    assert Session.copy(s).clipboard == nil
    assert %{entries: [_one]} = Session.copy(Session.select(s, [id], false)).clipboard
  end

  test "find_event and selected_events see notes and rests", %{session: session} do
    {:ok, s, id} = place(session, "C4", 0)

    assert Session.find_event(s, id).id == id
    assert Session.find_event(s, Ecto.UUID.generate()) == nil
    assert [%{id: ^id}] = Session.selected_events(Session.select(s, [id], false))
  end

  test "paste goes at the given tick, else the cursor, else after the selection, else the start",
       %{session: session} do
    {:ok, s, id} = place(session, "C4", 960)
    s = Session.select(s, [id], false)

    assert Session.paste_at(s, 480) == 480
    assert Session.paste_at(Session.put_cursor(s, 2880), nil) == 2880
    assert Session.paste_at(%{s | cursor: nil}, "junk") == 1920
    assert Session.paste_at(%{Session.clear_selection(s) | cursor: nil}, nil) == 0
  end

  test "paste never goes past the end of the score", %{session: session} do
    end_tick = Timeline.end_tick(session.score, session.ctx)
    assert Session.paste_at(session, 999_999) == end_tick
  end

  test "selecting one note or rest puts the cursor just after it; several leave it",
       %{session: session} do
    {:ok, s, c} = place(session, "C4", 960)
    {:ok, s, e} = place(s, "E4", 1920)

    assert Session.select(s, [c], false).cursor == 1920

    s = Session.put_cursor(s, 0)
    assert Session.select(s, [c, e], false).cursor == 0
    assert Session.clear_selection(Session.select(s, [e], false)).cursor == 2880
  end

  test "after placing, the cursor goes just after what was placed; unknown ids leave it",
       %{session: session} do
    {:ok, s, c} = place(session, "C4", 960)
    {:ok, s, e} = place(s, "E4", 0)

    assert Session.put_cursor_after(s, c).cursor == 1920
    assert Session.put_cursor_after(s, [e, c]).cursor == 1920

    s = Session.put_cursor(s, 0)
    assert Session.put_cursor_after(s, Ecto.UUID.generate()).cursor == 0
  end

  test "the cursor never sits past the end, after a put or an undo", %{session: session} do
    end_tick = Timeline.end_tick(session.score, session.ctx)
    assert Session.put_cursor(session, 999_999).cursor == end_tick

    {:ok, longer, _extra} = Session.edit(session, &Editing.append_measure/2)
    longer = Session.put_cursor(longer, end_tick + 960)

    assert Session.undo(longer).cursor == end_tick
  end

  defp place(session, spn, offset) do
    at = placement(spn, %{staff: :treble, offset: offset, value: :quarter})
    Session.edit(session, &Editing.place_note(&1, &2, 0, at))
  end
end
