defmodule DrawMusicWeb.EditorPlayTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusicWeb.EditorHelpers

  alias DrawMusicWeb.LibraryComponents

  setup :register_and_log_in_user

  setup %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "arm", %{"kind" => "note", "value" => "quarter"})
    place(view, 0, 0, "C4")
    place(view, 0, 960, "E4")
    place(view, 0, 1920, "G4")
    render_hook(view, "disarm", %{})
    play_mode(view)
    %{view: view}
  end

  defp play_mode(view), do: view |> element("#palette-mode-play") |> render_click()

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

  # At 100 BPM a quarter is 0.6 s. The span, not the last note, sets where a
  # loop repeats, so trailing rests are kept.
  test "the span's length is sent, rests included", %{view: view} do
    select(view, [0, 960])
    play(view)
    assert_push_event(view, "play", %{span: span})
    assert_in_delta span, 1.2, 1.0e-9

    render_hook(view, "stop", %{})
    render_hook(view, "clear_selection", %{})
    play(view)
    # Four empty-ending bars of 4/4: the whole score, not just to the G4.
    assert_push_event(view, "play", %{span: whole})
    assert_in_delta whole, 9.6, 1.0e-9
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

  test "a new selection while paused is played afresh, not resumed", %{view: view} do
    play(view)
    play(view)
    assert_push_event(view, "pause", %{})

    render_hook(view, "select_range", %{"from" => 0, "to" => 1000})
    assert_push_event(view, "stop", %{})
    assert has_element?(view, "#palette-play", "Play")

    play(view)
    assert_push_event(view, "play", %{events: [_first, _second], loop: false})
  end

  test "instruments that aren't installed are marked yellow in both pickers", %{view: view} do
    assert has_element?(view, "#playback-instrument option.text-warning", "(not installed)")

    view |> element("#palette-mode-edit") |> render_click()
    view |> element("#settings-button") |> render_click()
    assert has_element?(view, "#settings-instrument option.text-warning", "(not installed)")
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

  test "switching to Edit stops playback and swaps the play controls for the palette",
       %{view: view} do
    play(view)
    play(view)
    view |> element("#palette-mode-edit") |> render_click()

    assert_push_event(view, "stop", %{})
    refute has_element?(view, "#palette-play")
    assert has_element?(view, "#palette-quarter")

    play_mode(view)
    assert has_element?(view, "#palette-play", "Play")
  end

  test "in Edit mode the play events are ignored", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#palette-play")

    for event <- ~w(play rewind toggle_loop use_playback_instrument) do
      render_hook(view, event, %{})
    end

    render_hook(view, "set_playback_instrument", %{"instrument" => "73"})
    refute_push_event(view, "play", _payload)
    refute_push_event(view, "rewind", _payload)
    refute_push_event(view, "loop", _payload)
    assert :sys.get_state(view.pid).socket.assigns.playback_instrument == 0
  end

  test "nothing to play stays idle with a message", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    play_mode(view)
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

  describe "the playback instrument" do
    # A saved, unchanged version, so the unsaved marker means something.
    setup %{conn: conn, scope: scope} do
      version = DrawMusic.LibraryFixtures.version_fixture(scope)
      path = LibraryComponents.version_path(version.key.composition.id, version.key, 1)
      {:ok, view, _html} = live(conn, path)
      play_mode(view)
      %{view: view}
    end

    defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

    defp hear_as(view, program) do
      view
      |> element("#playback-instrument-form")
      |> render_change(%{"instrument" => to_string(program)})
    end

    test "starts as the version's and changes only playback", %{view: view} do
      assert has_element?(view, "#playback-instrument option[value='0'][selected]")
      assert has_element?(view, "#use-playback-instrument[disabled]")

      hear_as(view, 73)

      assert has_element?(view, ~s(#score-editor[data-instrument*='"program":73']))
      assert assigns(view).instrument == 0
      refute has_element?(view, "#dirty-marker")
      refute has_element?(view, "#use-playback-instrument[disabled]")
    end

    test "survives switching to Edit and back", %{view: view} do
      hear_as(view, 73)
      view |> element("#palette-mode-edit") |> render_click()
      view |> element("#palette-mode-play") |> render_click()

      assert has_element?(view, "#playback-instrument option[value='73'][selected]")
    end

    test "the set-instrument button asks first, then sets the version's instrument", %{view: view} do
      hear_as(view, 73)
      assert has_element?(view, "#use-playback-instrument[data-confirm*='Flute']")

      view |> element("#use-playback-instrument") |> render_click()

      assert assigns(view).instrument == 73
      assert has_element?(view, "#dirty-marker")
      assert has_element?(view, "#use-playback-instrument[disabled]")
    end

    test "an out-of-range program is ignored", %{view: view} do
      render_hook(view, "set_playback_instrument", %{"instrument" => "128"})
      assert assigns(view).playback_instrument == 0
    end
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
