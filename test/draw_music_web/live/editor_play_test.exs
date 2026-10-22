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

  test "Play sends the score's notes to the browser and shows Stop", %{view: view} do
    view |> element("#palette-play") |> render_click()

    assert_push_event(view, "play", %{events: [first, second]})
    assert {first.midi, first.start} == {60, 0.0}
    assert second.midi == 64
    assert has_element?(view, "#palette-play[aria-pressed=true]")
  end

  test "with a selection, Play starts at the selection", %{view: view} do
    render_hook(view, "select", %{"ids" => [id_at(view, 960)], "add" => false})
    view |> element("#palette-play") |> render_click()

    assert_push_event(view, "play", %{events: [only]})
    assert {only.midi, only.start} == {64, 0.0}
  end

  test "Stop and the end of playback reset the button", %{view: view} do
    view |> element("#palette-play") |> render_click()
    view |> element("#palette-play") |> render_click()
    assert_push_event(view, "stop", %{})
    refute has_element?(view, "#palette-play[aria-pressed=true]")

    view |> element("#palette-play") |> render_click()
    render_hook(view, "playback_ended", %{})
    refute has_element?(view, "#palette-play[aria-pressed=true]")
  end
end
