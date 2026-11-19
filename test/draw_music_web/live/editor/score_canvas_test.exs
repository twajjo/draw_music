defmodule DrawMusicWeb.Editor.ScoreCanvasTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.MusicHelpers

  alias DrawMusic.Engraving.Layout
  alias DrawMusic.Music.{Context, Score, Session}
  alias DrawMusicWeb.{Armed, ComponentHostLive, EditorGeometry, ScoreSvg}
  alias DrawMusicWeb.Editor.ScoreCanvas

  setup :register_and_log_in_user

  # One bar of 4/4 with C4 and E4 quarters on its first two beats.
  setup do
    ctx = %Context{}
    attrs = %{staff: :treble, value: :quarter}
    {score, c4} = note!(Score.new(1), ctx, 0, "C4", Map.put(attrs, :offset, 0))
    {score, e4} = note!(score, ctx, 0, "E4", Map.put(attrs, :offset, 960))
    %{score: score, ctx: ctx, c4: c4, e4: e4, session: Session.new(score, ctx)}
  end

  test "a click on a note selects it", %{conn: conn} = setup do
    view = host(conn, setup)
    hook(view, "select", %{"ids" => [setup.c4], "add" => false})

    assert_receive {:component_sent, {:editor, {:session, fun}}}
    assert selected(fun, setup) == [setup.c4]
  end

  test "a band previews what it would select, then selects it", %{conn: conn} = setup do
    view = host(conn, setup)

    hook(view, "preview_range", %{"from" => 0, "to" => 1920})
    assert_reply(view, %{ids: ids})
    assert setup.c4 in ids and setup.e4 in ids
    refute_received {:component_sent, _anything}

    hook(view, "select_range", %{"from" => 1920, "to" => 0})
    assert_receive {:component_sent, {:editor, {:session, fun}}}
    assert selected(fun, setup) == Enum.sort(ids)
  end

  test "a right-click on a note opens its menu; on the selection, the selection's",
       %{conn: conn} = setup do
    view = host(conn, setup)
    hook(view, "open_menu", %{"id" => setup.c4, "x" => 10, "y" => 10})
    assert_receive {:component_sent, {:editor, {:open, {:menu, %{ids: [id]}}}}}
    assert id == setup.c4

    view = host(conn, setup, %{session: with_selection(setup, [setup.c4, setup.e4])})
    hook(view, "open_menu", %{"id" => nil, "x" => 10, "y" => 10})
    assert_receive {:component_sent, {:editor, {:open, {:menu, %{ids: ids}}}}}
    assert Enum.sort(ids) == Enum.sort([setup.c4, setup.e4])
  end

  test "Esc or a right-click while placing disarms", %{conn: conn} = setup do
    view = host(conn, setup)
    hook(view, "disarm", %{})

    assert_receive {:component_sent, {:editor, {:palette, %{armed: nil}}}}
  end

  test "the armed item is placed where the score is clicked; a bad target is explained",
       %{conn: conn} = setup do
    armed = %Armed{kind: :note, value: :quarter}
    view = host(conn, setup, %{armed: armed, insert?: false})
    {step, _alter} = pitch!("G4")

    hook(view, "place", %{"measure" => 0, "offset" => 2880, "staff" => "treble", "step" => step})
    assert_receive {:component_sent, {:editor, {:edit, fun, :follow}}}
    assert {0, 2880, "G4", :quarter, 0} in edited(fun, setup.session)

    hook(view, "place", %{"measure" => -1, "offset" => 0, "staff" => "treble", "step" => step})
    assert_receive {:component_sent, {:editor, {:flash, :error, _message}}}
  end

  test "Delete edits the selection, and does nothing with none", %{conn: conn} = setup do
    view = host(conn, setup)
    hook(view, "delete", %{})
    refute_received {:component_sent, _anything}

    session = with_selection(setup, [setup.c4])
    view = host(conn, setup, %{session: session})
    hook(view, "delete", %{})
    assert_receive {:component_sent, {:editor, {:edit, fun}}}
    assert [{_measure, _offset, "E4", :quarter, 0}] = edited(fun, session)
  end

  test "a click on empty music puts the cursor there, and paste lands at it",
       %{conn: conn} = setup do
    session = setup |> with_selection([setup.c4]) |> Session.copy()
    view = host(conn, setup, %{session: session})

    hook(view, "set_cursor", %{"at" => 2880})
    assert_receive {:component_sent, {:editor, {:session, put}}}
    # The click also cleared the selection.
    session = session |> put.() |> Session.clear_selection()
    assert session.cursor == 2880

    send(view.pid, {:host_attrs, %{session: session}})
    hook(view, "paste", %{})
    assert_receive {:component_sent, {:editor, {:edit, fun, :follow}}}
    assert {0, 2880, "C4", :quarter, 0} in edited(fun, session)
  end

  test "the score says whether anything is selected, so the arrows know what to move",
       %{conn: conn} = setup do
    assert has_element?(host(conn, setup), "#score-editor[data-selected=false]")

    view = host(conn, setup, %{session: with_selection(setup, [setup.c4])})
    assert has_element?(view, "#score-editor[data-selected=true]")
  end

  # The bar's half rest (beats 3–4) trades places with E4 (beat 2).
  test "← on one selected rest moves it past the note before it, and keeps it selected",
       %{conn: conn} = setup do
    rest =
      Enum.find(setup.session.score.measures |> hd() |> Map.get(:rests), &(&1.staff == :treble))

    session = with_selection(setup, [rest.id])
    view = host(conn, setup, %{session: session})

    hook(view, "move", %{"dir" => "left"})
    assert_receive {:component_sent, {:editor, {:edit, fun, :select}}}
    assert {:ok, moved, [_still_selected]} = fun.(session.score, session.ctx)
    assert {0, 2880, "E4", :quarter, 0} in notes(moved)
  end

  test "the bar buttons add, insert and delete bars", %{conn: conn} = setup do
    view = host(conn, setup)

    view |> element("#add-measure") |> render_click()
    assert_receive {:component_sent, {:editor, {:edit, fun}}}
    {:ok, session, _extra} = Session.edit(setup.session, fun)
    assert length(session.score.measures) == 2

    view |> element("#measure-0-insert") |> render_click()
    assert_receive {:component_sent, {:editor, {:edit, _fun}}}
  end

  test "Play mode ignores the edits, and a click on a note sounds its chord",
       %{conn: conn} = setup do
    view = host(conn, setup, %{editor_mode: :play, armed: %Armed{kind: :note, value: :quarter}})
    hook(view, "open_menu", %{"id" => setup.c4, "x" => 10, "y" => 10})
    hook(view, "open_settings", %{})
    hook(view, "place", %{"measure" => 0, "offset" => 0, "staff" => "treble", "step" => 30})
    hook(view, "add_measure", %{})
    refute_received {:component_sent, _anything}

    hook(view, "audition", %{"id" => setup.c4})
    assert_push_event(view, "audition", %{events: [_one | _rest]})
    assert_receive {:component_sent, {:editor, {:session, fun}}}
    assert selected(fun, setup) == [setup.c4]
  end

  # The notes an `{:edit, fun}` intent leaves.
  defp edited(fun, %Session{} = session) do
    {:ok, session, _extra} = Session.edit(session, fun)
    notes(session.score)
  end

  defp hook(view, event, params) do
    view |> element("#score-editor") |> render_hook(event, params)
  end

  defp host(conn, %{score: score, ctx: ctx, session: session}, changes \\ %{}) do
    engraved = Layout.layout(score, ctx)

    attrs =
      Map.merge(
        %{
          session: session,
          engraved: engraved,
          pieces: ScoreSvg.pieces(engraved, :page),
          geometry_json: Jason.encode!(EditorGeometry.encode(engraved, ctx)),
          armed: nil,
          insert?: true,
          editor_mode: :edit,
          layout: :page,
          loading?: false,
          show_note_names?: false
        },
        changes
      )

    session = %{"component" => ScoreCanvas, "attrs" => attrs, "test_pid" => self()}
    {:ok, view, _html} = live_isolated(conn, ComponentHostLive, session: session)
    view
  end

  # The selection a `{:session, fun}` intent leaves.
  defp selected(fun, %{session: session}) do
    session |> fun.() |> Session.selection_ids() |> Enum.sort()
  end

  defp with_selection(%{session: session}, ids), do: Session.select(session, ids, false)
end
