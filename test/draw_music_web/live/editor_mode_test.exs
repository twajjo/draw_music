defmodule DrawMusicWeb.EditorModeTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusicWeb.EditorHelpers

  setup :register_and_log_in_user

  setup %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "lock", %{"kind" => "note", "value" => "quarter"})
    place(view, 0, 0, "C4")
    place(view, 0, 0, "E4")
    place(view, 0, 960, "G4")

    [c, e, g] =
      session_of(view).score.measures
      |> hd()
      |> Map.fetch!(:notes)
      |> Enum.sort_by(&{&1.offset, &1.step})
      |> Enum.map(& &1.id)

    %{view: view, c: c, e: e, g: g}
  end

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  defp play_mode(view), do: view |> element("#palette-mode-play") |> render_click()

  test "toggle_mode switches, disarms, and keeps the selection", %{view: view, g: g} do
    render_hook(view, "select", %{"ids" => [g], "add" => false})
    play_mode(view)

    assert assigns(view).armed == nil
    assert MapSet.to_list(session_of(view).selection) == [g]
    assert has_element?(view, "#score-editor[data-mode=play]")
    assert has_element?(view, "#palette-mode-play[aria-pressed=true]")

    render_hook(view, "toggle_mode", %{})
    assert has_element?(view, "#score-editor[data-mode=edit]")
  end

  test "editing events change nothing in play mode", %{view: view, c: c, g: g} do
    render_hook(view, "select", %{"ids" => [g], "add" => false})
    render_hook(view, "copy", %{})
    play_mode(view)
    before = {notes_of(view), session_of(view).undo, assigns(view).armed, assigns(view).insert?}

    edits = [
      {"lock", %{"kind" => "note", "value" => "half"}},
      {"arm_value", %{"value" => "eighth"}},
      {"arm_tie", %{}},
      {"place", %{"measure" => 0, "offset" => 1920, "staff" => "treble", "step" => 30}},
      {"move", %{"dir" => "up"}},
      {"move", %{"dir" => "right"}},
      {"drop", %{"ids" => [g], "steps" => 2}},
      {"delete", %{}},
      {"cut", %{}},
      {"paste", %{"at" => 1920}},
      {"undo", %{}},
      {"redo", %{}},
      {"tie", %{"from" => c, "to" => g}},
      {"toggle_dot", %{}},
      {"set_accidental", %{"alter" => "1"}},
      {"toggle_insert", %{}},
      {"toggle_rest", %{}},
      {"open_menu", %{"id" => g, "x" => 1, "y" => 1}},
      {"insert_measure", %{"index" => 0}},
      {"delete_measure", %{"index" => 0}},
      {"add_measure", %{}}
    ]

    for {event, params} <- edits, do: render_hook(view, event, params)

    assert {notes_of(view), session_of(view).undo, assigns(view).armed, assigns(view).insert?} ==
             before

    assert assigns(view).menu == nil
  end

  test "Play, Rewind, Loop and Stop still work in play mode", %{view: view} do
    play_mode(view)

    render_hook(view, "play", %{})
    assert_push_event(view, "play", %{events: [_, _, _]})
    render_hook(view, "rewind", %{})
    assert_push_event(view, "rewind", %{})
    render_hook(view, "toggle_loop", %{})
    assert_push_event(view, "loop", %{on: true})
    render_hook(view, "stop", %{})
    assert_push_event(view, "stop", %{})
  end

  test "audition pushes the chord and selects the note", %{view: view, e: e} do
    play_mode(view)
    render_hook(view, "audition", %{"id" => e})

    assert_push_event(view, "audition", %{events: events})
    assert events |> Enum.map(& &1.midi) |> Enum.sort() == [60, 64]
    assert MapSet.to_list(session_of(view).selection) == [e]
  end

  test "audition does nothing in edit mode", %{view: view, e: e} do
    render_hook(view, "audition", %{"id" => e})
    refute_push_event(view, "audition", _payload)
  end

  test "the palette's editing groups are inert in play mode", %{view: view} do
    refute has_element?(view, "#palette [data-group=editing][inert]")
    play_mode(view)
    assert has_element?(view, "#palette [data-group=editing][inert]")
  end
end
