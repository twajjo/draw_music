defmodule DrawMusicWeb.EditorReadingAidsTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.LibraryFixtures
  import DrawMusicWeb.EditorHelpers

  alias DrawMusic.Accounts
  alias DrawMusicWeb.LibraryComponents

  setup :register_and_log_in_user

  test "the staff letters are drawn in the editor only when turned on", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#score .reading-aid")

    view |> element("#account-menu-settings") |> render_click()
    prefer(view, letter_staves: "true")

    assert has_element?(view, "#score .reading-aid[data-aid=line]")
    assert has_element?(view, "#score .reading-aid[data-aid=middle_c]")
  end

  test "selected notes are named, and only while selected", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    placing_mode(view, :overlay)
    view |> element("#palette-quarter") |> render_click()
    place(view, 0, 0, "C4")
    place(view, 0, 960, "E4")
    [c, e] = note_ids(view)

    canvas_hook(view, "clear_selection", %{})
    refute has_element?(view, "#score .reading-aid[data-aid=note]")

    canvas_hook(view, "select", %{"ids" => [c, e], "add" => false})
    assert count(view, "#score .reading-aid[data-aid=note]") == 2
    assert has_element?(view, "#score .reading-aid[data-aid=note]", "E")

    canvas_hook(view, "select", %{"ids" => [c], "add" => false})
    assert count(view, "#score .reading-aid[data-aid=note]") == 1
  end

  test "selected notes go unnamed with the preference off", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    placing_mode(view, :overlay)
    view |> element("#palette-quarter") |> render_click()
    place(view, 0, 0, "C4")

    view |> element("#account-menu-settings") |> render_click()
    prefer(view, show_note_names: "false")
    canvas_hook(view, "select", %{"ids" => note_ids(view), "add" => false})

    refute has_element?(view, "#score .reading-aid[data-aid=note]")
  end

  test "every note is named, selected or not, with names at all times", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    placing_mode(view, :overlay)
    view |> element("#palette-quarter") |> render_click()
    place(view, 0, 0, "C4")
    place(view, 0, 960, "E4")
    canvas_hook(view, "clear_selection", %{})

    view |> element("#account-menu-settings") |> render_click()
    prefer(view, note_names_in_edit_only: "false")

    assert count(view, "#score .reading-aid[data-aid=note]") == 2
  end

  test "downloads never carry them, whatever the preference", %{conn: conn, scope: scope} do
    version = version_fixture(scope)
    prefs = %{letter_staves: true, show_note_names: true, note_names_in_edit_only: false}
    {:ok, _user} = Accounts.update_user_preferences(scope, prefs)

    {:ok, view, _html} = live(conn, path(version))
    assert has_element?(view, "#score .reading-aid")

    svg = conn |> get(path(version) <> "/score.svg") |> response(200)
    refute svg =~ "reading-aid"
  end

  # The first bar's note ids, in time order.
  defp note_ids(view) do
    session_of(view).score.measures
    |> hd()
    |> Map.fetch!(:notes)
    |> Enum.sort_by(& &1.offset)
    |> Enum.map(& &1.id)
  end

  defp path(version) do
    LibraryComponents.version_path(version.key.composition.id, version.key, version.number)
  end

  # A change in the open Preferences panel, previewed (not saved).
  defp prefer(view, fields) do
    view |> form("#preferences-form", user: Map.new(fields)) |> render_change()
  end
end
