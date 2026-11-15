defmodule DrawMusicWeb.Editor.ScoreCanvasTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.MusicHelpers

  alias DrawMusic.Engraving.Layout
  alias DrawMusic.Music.{Context, Score, Session}
  alias DrawMusicWeb.{ComponentHostLive, EditorGeometry, ScoreSvg}
  alias DrawMusicWeb.Editor.ScoreCanvas

  setup :register_and_log_in_user

  # One bar of 4/4 with C4 and E4 quarters on its first two beats.
  setup do
    ctx = %Context{}
    attrs = %{staff: :treble, value: :quarter}
    {score, c4} = note!(Score.new(1), ctx, 0, "C4", Map.put(attrs, :offset, 0))
    {score, e4} = note!(score, ctx, 0, "E4", Map.put(attrs, :offset, 960))
    %{score: score, ctx: ctx, c4: c4, e4: e4}
  end

  defp host(conn, %{score: score, ctx: ctx}, changes \\ %{}) do
    engraved = Layout.layout(score, ctx)

    attrs =
      Map.merge(
        %{
          score: score,
          ctx: ctx,
          selection: MapSet.new(),
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

  defp hook(view, event, params) do
    view |> element("#score-editor") |> render_hook(event, params)
  end

  # The selection a `{:session, fun}` intent leaves.
  defp selected(fun, %{score: score, ctx: ctx}) do
    score |> Session.new(ctx) |> fun.() |> Session.selection_ids() |> Enum.sort()
  end

  test "a click on a note selects it", %{conn: conn} = setup do
    view = host(conn, setup)
    hook(view, "select", %{"ids" => [setup.c4], "add" => false})

    assert_received {:component_sent, {:editor, {:session, fun}}}
    assert selected(fun, setup) == [setup.c4]
  end

  test "a band previews what it would select, then selects it", %{conn: conn} = setup do
    view = host(conn, setup)

    hook(view, "preview_range", %{"from" => 0, "to" => 1920})
    assert_reply(view, %{ids: ids})
    assert setup.c4 in ids and setup.e4 in ids
    refute_received {:component_sent, _anything}

    hook(view, "select_range", %{"from" => 1920, "to" => 0})
    assert_received {:component_sent, {:editor, {:session, fun}}}
    assert selected(fun, setup) == Enum.sort(ids)
  end

  test "a right-click on a note opens its menu; on the selection, the selection's",
       %{conn: conn} = setup do
    view = host(conn, setup)
    hook(view, "open_menu", %{"id" => setup.c4, "x" => 10, "y" => 10})
    assert_received {:component_sent, {:editor, {:open, {:menu, %{ids: [id]}}}}}
    assert id == setup.c4

    view = host(conn, setup, %{selection: MapSet.new([setup.c4, setup.e4])})
    hook(view, "open_menu", %{"id" => nil, "x" => 10, "y" => 10})
    assert_received {:component_sent, {:editor, {:open, {:menu, %{ids: ids}}}}}
    assert Enum.sort(ids) == Enum.sort([setup.c4, setup.e4])
  end

  test "Esc or a right-click while placing disarms", %{conn: conn} = setup do
    view = host(conn, setup)
    hook(view, "disarm", %{})

    assert_received {:component_sent, {:editor, {:palette, %{armed: nil}}}}
  end

  test "Play mode ignores the edits, and a click on a note sounds its chord",
       %{conn: conn} = setup do
    view = host(conn, setup, %{editor_mode: :play})
    hook(view, "open_menu", %{"id" => setup.c4, "x" => 10, "y" => 10})
    hook(view, "open_settings", %{})
    refute_received {:component_sent, _anything}

    hook(view, "audition", %{"id" => setup.c4})
    assert_push_event(view, "audition", %{events: [_one | _rest]})
    assert_received {:component_sent, {:editor, {:session, fun}}}
    assert selected(fun, setup) == [setup.c4]
  end
end
