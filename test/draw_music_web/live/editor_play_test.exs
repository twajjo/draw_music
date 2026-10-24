defmodule DrawMusicWeb.EditorPlayTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusicWeb.EditorHelpers

  setup :register_and_log_in_user

  setup %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "lock", %{"kind" => "note", "value" => "quarter"})
    place(view, 0, 0, "C4")
    place(view, 0, 960, "E4")
    place(view, 0, 1920, "G4")
    render_hook(view, "disarm", %{})
    %{view: view}
  end

  defp id_at(view, offset) do
    session_of(view).score.measures
    |> hd()
    |> Map.fetch!(:notes)
    |> Enum.find(&(&1.offset == offset))
    |> Map.fetch!(:id)
  end

  defp select(view, offsets) do
    render_hook(view, "select", %{"ids" => Enum.map(offsets, &id_at(view, &1)), "add" => false})
  end

  defp play(view), do: view |> element("#palette-play") |> render_click()

  test "Play sends the score's notes to the browser and shows Pause", %{view: view} do
    play(view)

    assert_push_event(view, "play", %{events: [first, second, third], loop: false})
    assert {first.midi, first.start} == {60, 0.0}
    assert {second.midi, third.midi} == {64, 67}
    assert has_element?(view, "#palette-play[aria-pressed=true]", "Pause")
  end

  test "a range selection plays only that range", %{view: view} do
    select(view, [0, 960])
    play(view)

    assert_push_event(view, "play", %{events: events})
    assert Enum.map(events, & &1.midi) == [60, 64]
  end

  test "a single selection plays from it to the end", %{view: view} do
    select(view, [960])
    play(view)

    assert_push_event(view, "play", %{events: [first, second]})
    assert {first.midi, first.start, second.midi} == {64, 0.0, 67}
  end

  test "Play while playing pauses; again resumes", %{view: view} do
    play(view)
    play(view)
    assert_push_event(view, "pause", %{})
    assert has_element?(view, "#palette-play", "Resume")

    play(view)
    assert_push_event(view, "resume", %{})
    assert has_element?(view, "#palette-play", "Pause")
  end

  test "Rewind pushes rewind; Loop toggles and pushes loop", %{view: view} do
    view |> element("#palette-rewind") |> render_click()
    assert_push_event(view, "rewind", %{})

    view |> element("#palette-loop") |> render_click()
    assert_push_event(view, "loop", %{on: true})
    assert has_element?(view, "#palette-loop[aria-pressed=true]")

    play(view)
    assert_push_event(view, "play", %{loop: true})
  end

  test "Stop, and the end of playback, reset the button", %{view: view} do
    play(view)
    render_hook(view, "stop", %{})
    assert_push_event(view, "stop", %{})
    refute has_element?(view, "#palette-play[aria-pressed=true]")

    play(view)
    render_hook(view, "playback_ended", %{})
    assert has_element?(view, "#palette-play", "Play")
  end

  test "an edit while paused stops playback", %{view: view} do
    play(view)
    play(view)
    render_hook(view, "lock", %{"kind" => "note", "value" => "quarter"})
    place(view, 0, 2880, "B4")

    assert_push_event(view, "stop", %{})
    assert has_element?(view, "#palette-play", "Play")
  end

  test "nothing to play stays idle with a message", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    play(view)

    refute_push_event(view, "play", _payload)
    assert has_element?(view, "#flash-error", "Nothing to play here.")
    assert has_element?(view, "#palette-play", "Play")
  end

  test "while the instrument loads, the button says so", %{view: view} do
    render_hook(view, "playback_state", %{"state" => "loading"})
    assert has_element?(view, "#palette-play", "Loading Acoustic Grand Piano…")

    render_hook(view, "playback_state", %{"state" => "ready"})
    assert has_element?(view, "#palette-play", "Play")
  end

  test "a fallback from the hook shows a notice naming the instrument", %{view: view} do
    render_hook(view, "playback_state", %{"state" => "fallback"})

    assert has_element?(
             view,
             "#flash-info",
             "Acoustic Grand Piano isn't available; playing with the built-in synth."
           )
  end
end
