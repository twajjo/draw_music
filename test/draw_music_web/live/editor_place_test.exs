defmodule DrawMusicWeb.EditorPlaceTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.LibraryFixtures
  import DrawMusicWeb.EditorHelpers

  alias DrawMusicWeb.LibraryComponents

  setup :register_and_log_in_user

  defp draft(conn) do
    {:ok, view, _html} = live(conn, ~p"/")
    view
  end

  defp arm(view, value), do: view |> element("#palette-#{value}") |> render_click()

  test "a placed note appears and the item is disarmed", %{conn: conn} do
    view = draft(conn)
    arm(view, "eighth")
    place(view, 0, 480, "G4")

    assert notes_of(view) == [{0, 480, "G4", :eighth, 0}]
    assert count(view, "#score [id^='note-']") == 1
    refute has_element?(view, "#palette-eighth[aria-pressed=true]")
  end

  test "a locked item stays armed for further placements", %{conn: conn} do
    view = draft(conn)
    render_hook(view, "lock", %{"kind" => "note", "value" => "quarter"})
    place(view, 0, 0, "C4")
    place(view, 0, 960, "D4")

    assert length(notes_of(view)) == 2
    assert has_element?(view, "#palette-quarter[aria-pressed=true]")
  end

  test "the key signature supplies the accidental unless one is given", %{
    conn: conn,
    scope: scope
  } do
    version = version_fixture(scope, key: %{sf: 2})

    {:ok, view, _html} =
      live(conn, LibraryComponents.version_path(version.key.composition.id, version.key, 1))

    render_hook(view, "lock", %{"kind" => "note", "value" => "quarter"})
    place(view, 0, 0, "F4")
    place(view, 0, 960, "F4", alter: true)

    assert [{0, 0, "F♯4", :quarter, 0}, {0, 960, "F4", :quarter, 0}] = notes_of(view)
  end

  test "a refused placement explains why and keeps the item armed", %{conn: conn} do
    view = draft(conn)
    arm(view, "half")
    place(view, 0, 2880, "C4")

    assert has_element?(view, "#flash-error", "That bar is full")
    assert has_element?(view, "#palette-half[aria-pressed=true]")
    assert notes_of(view) == []
  end

  test "a click on a bar that no longer exists is refused", %{conn: conn} do
    view = draft(conn)
    arm(view, "quarter")
    place(view, 99, 0, "C4")

    assert has_element?(view, "#flash-error", "That bar no longer exists")
  end

  test "forged placement params are ignored", %{conn: conn} do
    view = draft(conn)
    arm(view, "quarter")

    for bad <- [
          %{"measure" => 0, "offset" => 0, "staff" => "alto", "step" => 28},
          %{"measure" => 0, "offset" => 0, "staff" => "treble", "step" => "x"},
          %{"measure" => 0, "offset" => 0, "staff" => "treble", "step" => 28, "alter" => 9},
          %{"measure" => -1, "offset" => 0, "staff" => "treble", "step" => 28}
        ] do
      render_hook(view, "place", bad)
    end

    assert notes_of(view) == []
    assert has_element?(view, "#palette-quarter[aria-pressed=true]")
  end

  test "Insert mode moves later music on that staff right", %{conn: conn} do
    view = draft(conn)
    arm(view, "quarter")
    place(view, 0, 0, "C4")
    arm(view, "whole")
    place(view, 0, 0, "C3", staff: "bass")

    view |> element("#palette-insert") |> render_click()
    arm(view, "quarter")
    place(view, 0, 0, "E4")

    assert notes_of(view) == [
             {0, 0, "C3", :whole, 0},
             {0, 0, "E4", :quarter, 0},
             {0, 960, "C4", :quarter, 0}
           ]
  end

  test "a chord quality builds on the clicked note", %{conn: conn} do
    view = draft(conn)
    view |> element("#palette-chord-major") |> render_click()
    place(view, 0, 0, "C4")

    assert Enum.map(notes_of(view), &elem(&1, 2)) == ["C4", "E4", "G4"]
  end

  test "a scale degree builds the key's chord in the clicked octave", %{conn: conn, scope: scope} do
    version = version_fixture(scope, key: %{sf: 1})

    {:ok, view, _html} =
      live(conn, LibraryComponents.version_path(version.key.composition.id, version.key, 1))

    view |> element("#palette-degree-5") |> render_click()
    place(view, 0, 0, "C4")

    assert Enum.map(notes_of(view), &elem(&1, 2)) == ["D4", "F♯4", "A4"]
  end

  test "an armed rest places a rest", %{conn: conn} do
    view = draft(conn)
    view |> element("#palette-rest-toggle") |> render_click()
    arm(view, "quarter")
    place(view, 0, 0, "B4")

    assert count(view, "#score [id^='rest-']") == 1
    assert notes_of(view) == []
  end

  test "the hook element carries the geometry and the armed item", %{conn: conn} do
    view = draft(conn)
    assert has_element?(view, "#score-editor[data-geometry]")
    arm(view, "eighth")
    assert has_element?(view, "#score-editor[data-armed*='eighth']")
  end
end
