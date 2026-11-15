defmodule DrawMusicWeb.EditorReadingAidsTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.LibraryFixtures
  import DrawMusicWeb.EditorHelpers

  alias DrawMusic.Accounts
  alias DrawMusicWeb.LibraryComponents

  setup :register_and_log_in_user

  defp path(version) do
    LibraryComponents.version_path(version.key.composition.id, version.key, version.number)
  end

  # The first bar's note ids, in time order.
  defp note_ids(view) do
    session_of(view).score.measures
    |> hd()
    |> Map.fetch!(:notes)
    |> Enum.sort_by(& &1.offset)
    |> Enum.map(& &1.id)
  end

  test "the staff letters are drawn in the editor only when turned on", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#score .reading-aid")

    view |> element("#account-menu-settings") |> render_click()
    view |> element("#settings-letter-staves") |> render_change(%{"value" => "true"})

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

    render_hook(view, "clear_selection", %{})
    refute has_element?(view, "#score .reading-aid[data-aid=note]")

    render_hook(view, "select", %{"ids" => [c, e], "add" => false})
    assert count(view, "#score .reading-aid[data-aid=note]") == 2
    assert has_element?(view, "#score .reading-aid[data-aid=note]", "E")

    render_hook(view, "select", %{"ids" => [c], "add" => false})
    assert count(view, "#score .reading-aid[data-aid=note]") == 1
  end

  test "selected notes go unnamed with the preference off", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    placing_mode(view, :overlay)
    view |> element("#palette-quarter") |> render_click()
    place(view, 0, 0, "C4")

    view |> element("#account-menu-settings") |> render_click()
    view |> element("#settings-name-notes") |> render_change(%{"value" => "false"})
    render_hook(view, "select", %{"ids" => note_ids(view), "add" => false})

    refute has_element?(view, "#score .reading-aid[data-aid=note]")
  end

  test "downloads never carry them, whatever the preference", %{conn: conn, scope: scope} do
    version = version_fixture(scope)
    prefs = %{letter_staves: true, name_notes: true}
    {:ok, _user} = Accounts.update_user_preferences(scope, prefs)

    {:ok, view, _html} = live(conn, path(version))
    assert has_element?(view, "#score .reading-aid")

    svg = conn |> get(path(version) <> "/score.svg") |> response(200)
    refute svg =~ "reading-aid"
  end
end
