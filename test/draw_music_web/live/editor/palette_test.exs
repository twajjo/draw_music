defmodule DrawMusicWeb.Editor.PaletteTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DrawMusic.Music.{Context, Score, Session}
  alias DrawMusicWeb.{Armed, ComponentHostLive}
  alias DrawMusicWeb.Editor.Palette

  setup :register_and_log_in_user

  defp host(conn, attrs) do
    session = %{"component" => Palette, "attrs" => attrs, "test_pid" => self()}
    {:ok, view, _html} = live_isolated(conn, ComponentHostLive, session: session)
    view
  end

  defp click(view, selector), do: view |> element(selector) |> render_click()

  defp key_event(view, event, params \\ %{}) do
    view |> element("#palette") |> render_hook(event, params)
  end

  test "a length arms that note", %{conn: conn} do
    conn |> host(%{}) |> click("#palette-quarter")

    assert_receive {:component_sent, {:editor, {:palette, %{armed: armed}}}}
    assert %Armed{kind: :note, value: :quarter} = armed
  end

  test "the number keys arm a length of the row's kind", %{conn: conn} do
    conn |> host(%{row_kind: :rest}) |> key_event("arm_value", %{"value" => "half"})

    assert_receive {:component_sent, {:editor, {:palette, %{armed: armed}}}}
    assert %Armed{kind: :rest, value: :half} = armed
  end

  test "the rest toggle reports the row and what stays armed", %{conn: conn} do
    conn |> host(%{}) |> click("#palette-rest-toggle")
    assert_receive {:component_sent, {:editor, {:palette, %{row_kind: :rest, armed: nil}}}}
  end

  test "Insert/Overlay reports the switched mode", %{conn: conn} do
    conn |> host(%{insert?: true}) |> click("#palette-insert")
    assert_receive {:component_sent, {:editor, {:palette, %{insert?: false}}}}
  end

  test "with nothing armed, the dot and accidentals edit the selection", %{conn: conn} do
    view = host(conn, %{selection: ["a-note"]})

    click(view, "#palette-dot")
    assert_receive {:component_sent, {:editor, {:edit, dots}}}
    assert is_function(dots, 2)

    click(view, "#palette-sharp")
    assert_receive {:component_sent, {:editor, {:edit, sharp}}}
    assert is_function(sharp, 2)
  end

  test "a chord with notes selected and nothing armed turns them into it", %{conn: conn} do
    conn |> host(%{selection: ["a-note"]}) |> click("#palette-chord-major")
    assert_receive {:component_sent, {:editor, {:edit, _chordify, :select}}}
  end

  test "chords don't apply to rests", %{conn: conn} do
    conn |> host(%{row_kind: :rest}) |> key_event("arm_chord", %{"quality" => "major"})
    refute_receive {:component_sent, _anything}
  end

  test "select all selects every note, rest and tempo change", %{conn: conn} do
    conn |> host(%{}) |> click("#palette-select-all")
    assert_receive {:component_sent, {:editor, {:session, select_all}}}

    session = select_all.(Session.new(Score.new(1), %Context{}))
    assert MapSet.size(session.selection) > 0
  end

  test "the mode buttons, undo, redo and settings report their intents", %{conn: conn} do
    view = host(conn, %{can_undo?: true, can_redo?: true})

    click(view, "#palette-mode-play")
    assert_receive {:component_sent, {:editor, {:mode, :play}}}

    click(view, "#palette-undo")
    assert_receive {:component_sent, {:editor, {:history, :undo}}}

    click(view, "#palette-redo")
    assert_receive {:component_sent, {:editor, {:history, :redo}}}

    click(view, "#settings-button")
    assert_receive {:component_sent, {:editor, {:open, :settings}}}
  end

  test "in Play mode the edit tools are gone and their keys do nothing", %{conn: conn} do
    view = host(conn, %{editor_mode: :play})

    refute has_element?(view, "#palette-edit")
    assert has_element?(view, "#palette-play-controls")

    key_event(view, "select_all")
    key_event(view, "undo")
    refute_receive {:component_sent, _anything}

    key_event(view, "toggle_mode")
    assert_receive {:component_sent, {:editor, {:mode, :edit}}}
  end
end
