defmodule DrawMusicWeb.EditorPaletteTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  setup %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    %{view: view}
  end

  test "clicking a value arms it", %{view: view} do
    refute has_element?(view, "#palette-eighth[aria-pressed=true]")
    view |> element("#palette-eighth") |> render_click()
    assert has_element?(view, "#palette-eighth[aria-pressed=true]")
  end

  # Browsers send a clicked button's own `value` as the event's "value",
  # replacing phx-value-value; LiveViewTest doesn't, so check the attribute.
  test "value buttons carry their value for the browser", %{view: view} do
    assert has_element?(view, "#palette-quarter[value=quarter]")
    view |> element("#palette-rest-toggle") |> render_click()
    assert has_element?(view, "#palette-eighth[value=eighth]")
  end

  test "arming the same item twice keeps it armed", %{view: view} do
    view |> element("#palette-eighth") |> render_click()
    view |> element("#palette-eighth") |> render_click()
    assert has_element?(view, "#palette-eighth[aria-pressed=true]")
  end

  test "disarm clears the armed item", %{view: view} do
    view |> element("#palette-quarter") |> render_click()
    render_hook(view, "disarm", %{})
    refute has_element?(view, "#palette [aria-pressed=true][data-value]")
  end

  test "unknown values are not armed", %{view: view} do
    render_hook(view, "arm", %{"kind" => "note", "value" => "bogus"})
    refute has_element?(view, "#palette [aria-pressed=true][data-value]")
  end

  test "the rest toggle switches the value row to rests and keeps the armed value", %{view: view} do
    view |> element("#palette-eighth") |> render_click()
    view |> element("#palette-rest-toggle") |> render_click()

    assert has_element?(view, "#palette-eighth[data-kind=rest][aria-pressed=true]")
    assert has_element?(view, "#palette-rest-toggle[aria-pressed=true]")
  end

  test "dot and accidentals modify the armed item", %{view: view} do
    view |> element("#palette-quarter") |> render_click()

    view |> element("#palette-dot") |> render_click()
    assert has_element?(view, "#palette-dot[aria-pressed=true]")

    view |> element("#palette-sharp") |> render_click()
    assert has_element?(view, "#palette-sharp[aria-pressed=true]")

    view |> element("#palette-sharp") |> render_click()
    refute has_element?(view, "#palette-sharp[aria-pressed=true]")
  end

  test "the tie tool and chords arm their own kind", %{view: view} do
    view |> element("#palette-tie") |> render_click()
    assert has_element?(view, "#palette-tie[aria-pressed=true]")

    view |> element("#palette-chord-major") |> render_click()
    assert has_element?(view, "#palette-chords[aria-pressed=true]")
    refute has_element?(view, "#palette-tie[aria-pressed=true]")
  end

  test "placing starts in Insert mode; the Overlay/Insert button toggles it", %{view: view} do
    assert has_element?(view, "#palette-insert[aria-pressed=true]", "Insert")
    view |> element("#palette-insert") |> render_click()
    assert has_element?(view, "#palette-insert[aria-pressed=false]", "Overlay")
    view |> element("#palette-insert") |> render_click()
    assert has_element?(view, "#palette-insert[aria-pressed=true]", "Insert")
  end

  test "undo and redo are disabled with no history", %{view: view} do
    assert has_element?(view, "#palette-undo[disabled]")
    assert has_element?(view, "#palette-redo[disabled]")
  end
end
