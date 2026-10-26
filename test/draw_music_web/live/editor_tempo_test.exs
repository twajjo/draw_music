defmodule DrawMusicWeb.EditorTempoTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusicWeb.EditorHelpers

  setup :register_and_log_in_user

  # A draft with C4 and E4 quarters at the start of bar 0, at 100 BPM.
  setup %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "arm", %{"kind" => "note", "value" => "quarter"})
    place(view, 0, 0, "C4")
    place(view, 0, 960, "E4")
    render_hook(view, "disarm", %{})
    %{view: view}
  end

  defp tempos(view), do: session_of(view).score.tempos

  defp e4_id(view) do
    session_of(view).score.measures
    |> hd()
    |> Map.fetch!(:notes)
    |> Enum.find(&(&1.offset == 960))
    |> Map.fetch!(:id)
  end

  # Right-click the E4, "Tempo change here…", fill in the dialog (ticking
  # "Gradually" first shows its fields).
  defp add_tempo(view, params) do
    render_hook(view, "open_menu", %{"id" => e4_id(view), "x" => 10, "y" => 10})
    view |> element("#menu-tempo") |> render_click()

    if params[:gradual] == "true" do
      view |> form("#tempo-form", tempo: %{gradual: "true"}) |> render_change()
    end

    view |> form("#tempo-form", tempo: params) |> render_submit()
  end

  test "a note's menu adds a tempo mark where the note starts, drawn and selected", %{view: view} do
    render_hook(view, "open_menu", %{"id" => e4_id(view), "x" => 10, "y" => 10})
    view |> element("#menu-tempo") |> render_click()

    # The dialog starts at the tempo in force there.
    assert has_element?(view, "#tempo-form input[name='tempo[bpm]'][value='100']")

    view |> form("#tempo-form", tempo: %{bpm: "60"}) |> render_submit()

    assert [%{id: id, tick: 960, bpm: 60, to_tick: nil}] = tempos(view)
    refute has_element?(view, "#tempo-dialog")
    assert has_element?(view, "#tempo-#{id}")
    assert has_element?(view, "[data-tempo-id='#{id}'].selected")
  end

  test "a rit. reaches its tempo over the beats given, and has a draggable end", %{view: view} do
    add_tempo(view, %{bpm: "80", gradual: "true", to_bpm: "50", beats: "2"})

    assert [%{id: id, tick: 960, bpm: 80, to_tick: 2880, to_bpm: 50}] = tempos(view)
    assert has_element?(view, "#tempo-end-#{id}")
  end

  test "bad values are shown and nothing is saved", %{view: view} do
    add_tempo(view, %{bpm: "2"})

    assert tempos(view) == []
    assert has_element?(view, "#tempo-dialog")
    assert has_element?(view, "#tempo-form", "must be 5–400")
  end

  test "a mark opens its dialog to change or delete it", %{view: view} do
    add_tempo(view, %{bpm: "60"})
    [%{id: id}] = tempos(view)

    render_hook(view, "edit_tempo", %{"id" => id})
    assert has_element?(view, "#tempo-form input[name='tempo[bpm]'][value='60']")
    view |> form("#tempo-form", tempo: %{bpm: "72"}) |> render_submit()
    assert [%{id: ^id, bpm: 72}] = tempos(view)

    render_hook(view, "edit_tempo", %{"id" => id})
    view |> element("#tempo-delete") |> render_click()
    assert tempos(view) == []
  end

  test "dragging a mark moves it; dragging a rit.'s end resizes it", %{view: view} do
    add_tempo(view, %{bpm: "80", gradual: "true", to_bpm: "50", beats: "1"})
    [%{id: id}] = tempos(view)

    render_hook(view, "move_tempo", %{"id" => id, "tick" => 0})
    assert [%{tick: 0, to_tick: 960}] = tempos(view)

    render_hook(view, "resize_tempo", %{"id" => id, "tick" => 3840})
    assert [%{tick: 0, to_tick: 3840}] = tempos(view)
  end

  test "Delete removes a selected mark and leaves the notes; Undo brings it back", %{view: view} do
    add_tempo(view, %{bpm: "60"})
    render_hook(view, "delete", %{})

    assert tempos(view) == []
    assert length(notes_of(view)) == 2

    view |> element("#palette-undo") |> render_click()
    assert [%{bpm: 60}] = tempos(view)
  end

  test "Select all takes in tempo marks", %{view: view} do
    add_tempo(view, %{bpm: "60"})
    [%{id: id}] = tempos(view)
    render_hook(view, "clear_selection", %{})

    render_hook(view, "select_all", %{})
    assert has_element?(view, "[data-tempo-id='#{id}'].selected")
  end

  test "Play follows the tempo change", %{view: view} do
    add_tempo(view, %{bpm: "60"})
    view |> element("#palette-mode-play") |> render_click()
    view |> element("#palette-play") |> render_click()

    # C4 is a quarter at 100 BPM (0.6 s); E4 then sounds a whole second.
    assert_push_event(view, "play", %{events: [c4, e4]})
    assert_in_delta e4.start, 0.6, 1.0e-9
    assert_in_delta e4.duration, 1.0, 1.0e-9
    assert c4.duration < e4.duration
  end
end
