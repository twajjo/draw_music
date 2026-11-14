defmodule DrawMusicWeb.Editor.TransportTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DrawMusic.Engraving.Layout
  alias DrawMusic.Music.{Context, Note, Score, Session}
  alias DrawMusicWeb.ComponentHostLive
  alias DrawMusicWeb.Editor.Transport

  setup :register_and_log_in_user

  # Two bars of 4/4: a C4 quarter on beat 1 of each.
  setup do
    ctx = %Context{}
    notes = [note(0), note(3840)]
    [first, second] = Score.new(2).measures

    score = %Score{
      measures: [%{first | notes: [hd(notes)]}, %{second | notes: [List.last(notes)]}]
    }

    attrs = %{
      score: score,
      ctx: ctx,
      selection: MapSet.new(),
      engraved: Layout.layout(score, ctx),
      editor_mode: :play,
      instrument: 0,
      lines?: true
    }

    %{attrs: attrs, notes: notes}
  end

  defp note(offset_in_score) do
    %Note{
      id: Ecto.UUID.generate(),
      staff: :treble,
      offset: rem(offset_in_score, 3840),
      value: :quarter,
      step: 28
    }
  end

  defp host(conn, attrs) do
    session = %{"component" => Transport, "attrs" => attrs, "test_pid" => self()}
    {:ok, view, _html} = live_isolated(conn, ComponentHostLive, session: session)
    view
  end

  defp click(view, selector), do: view |> element(selector) |> render_click()

  defp hook(view, event, params \\ %{}) do
    view |> element("#transport") |> render_hook(event, params)
  end

  # The page re-renders the transport with new inputs.
  defp give(view, changes) do
    send(view.pid, {:host_attrs, changes})
    render(view)
  end

  test "Play plays; again pauses; again resumes", %{conn: conn, attrs: attrs} do
    view = host(conn, attrs)

    click(view, "#palette-play")
    assert_push_event(view, "play", %{events: [_first, _second], loop: false})
    assert has_element?(view, "#palette-play[aria-pressed=true]", "Pause")

    click(view, "#palette-play")
    assert_push_event(view, "pause", %{})
    assert has_element?(view, "#palette-play", "Resume")

    click(view, "#palette-play")
    assert_push_event(view, "resume", %{})
  end

  test "Loop is pushed and played with", %{conn: conn, attrs: attrs} do
    view = host(conn, attrs)

    click(view, "#palette-loop")
    assert_push_event(view, "loop", %{on: true})

    click(view, "#palette-play")
    assert_push_event(view, "play", %{loop: true})
  end

  test "before playing, a skip moves the start point by selecting", %{
    conn: conn,
    attrs: attrs,
    notes: [_c, second]
  } do
    view = host(conn, attrs)
    click(view, "#palette-skip-measure")

    assert_receive {:component_sent, {:editor, {:session, select}}}
    session = select.(Session.new(attrs.score, attrs.ctx))
    assert MapSet.to_list(session.selection) == [second.id]
  end

  test "while playing, a skip goes to the browser with where measures start", %{
    conn: conn,
    attrs: attrs
  } do
    view = host(conn, attrs)
    click(view, "#palette-play")
    click(view, "#palette-skip-measure")

    assert_push_event(view, "skip", %{by: "measure", back: false, starts: [0, 3840]})
  end

  test "nothing to play reports a message", %{conn: conn, attrs: attrs} do
    score = Score.new(1)
    view = host(conn, %{attrs | score: score, engraved: Layout.layout(score, attrs.ctx)})
    click(view, "#palette-play")

    refute_push_event(view, "play", _payload)
    assert_receive {:component_sent, {:editor, {:flash, :error, "Nothing to play here."}}}
  end

  test "a new score stops playback", %{conn: conn, attrs: attrs} do
    view = host(conn, attrs)
    click(view, "#palette-play")

    give(view, %{score: Score.new(2)})
    assert_push_event(view, "stop", %{})
    assert has_element?(view, "#palette-play", "Play")
  end

  test "a new selection drops a paused span; while playing it doesn't", %{
    conn: conn,
    attrs: attrs,
    notes: [c, second]
  } do
    view = host(conn, attrs)
    click(view, "#palette-play")

    give(view, %{selection: MapSet.new([c.id])})
    refute_push_event(view, "stop", _payload)

    click(view, "#palette-play")
    give(view, %{selection: MapSet.new([second.id])})
    assert_push_event(view, "stop", %{})
    assert has_element?(view, "#palette-play", "Play")
  end

  test "Edit mode stops playback and hides the controls, but keeps the transport", %{
    conn: conn,
    attrs: attrs
  } do
    view = host(conn, attrs)
    click(view, "#palette-play")
    assert_push_event(view, "play", _payload)

    give(view, %{editor_mode: :edit})
    assert_push_event(view, "stop", %{})
    refute has_element?(view, "#palette-play")
    assert has_element?(view, "#transport")

    hook(view, "play")
    refute_push_event(view, "play", _payload)
  end

  test "the playback instrument follows a new version instrument", %{conn: conn, attrs: attrs} do
    view = host(conn, attrs)
    assert has_element?(view, ~s(#transport[data-instrument*='"program":0']))

    give(view, %{instrument: 73})
    assert has_element?(view, ~s(#transport[data-instrument*='"program":73']))
  end

  test "Set … version Instrument reports the playback instrument", %{conn: conn, attrs: attrs} do
    view = host(conn, attrs)
    view |> element("#playback-instrument-form") |> render_change(%{"instrument" => "73"})
    assert has_element?(view, ~s(#transport[data-instrument*='"program":73']))

    click(view, "#use-playback-instrument")
    assert_receive {:component_sent, {:editor, {:instrument, 73}}}
  end

  test "a fallback reports a notice naming the instrument", %{conn: conn, attrs: attrs} do
    conn |> host(attrs) |> hook("playback_state", %{"state" => "fallback"})

    assert_receive {:component_sent, {:editor, {:flash, :info, message}}}
    assert message =~ "Acoustic Grand Piano isn't available"
  end

  test "before playing, Stop and Rewind clear the selection: back to the beginning", %{
    conn: conn,
    attrs: attrs
  } do
    view = host(conn, attrs)

    for button <- ~w(#palette-stop #palette-rewind) do
      click(view, button)
      assert_receive {:component_sent, {:editor, {:session, clear}}}
      assert clear.(Session.new(attrs.score, attrs.ctx)).selection == MapSet.new()
    end

    refute_push_event(view, "stop", _payload)
    refute_push_event(view, "rewind", _payload)
  end
end
