defmodule DrawMusicWeb.EditorReadingAidsTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.LibraryFixtures

  alias DrawMusic.Accounts
  alias DrawMusicWeb.LibraryComponents

  setup :register_and_log_in_user

  defp path(version) do
    LibraryComponents.version_path(version.key.composition.id, version.key, version.number)
  end

  test "the staff letters are drawn in the editor only when turned on", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#score .reading-aid")

    view |> element("#account-menu-settings") |> render_click()
    view |> element("#settings-letter-staves") |> render_change(%{"value" => "true"})

    assert has_element?(view, "#score .reading-aid[data-aid=line]")
    assert has_element?(view, "#score .reading-aid[data-aid=middle_c]")
  end

  test "downloads never carry them, whatever the preference", %{conn: conn, scope: scope} do
    version = version_fixture(scope)
    {:ok, _user} = Accounts.update_user_preferences(scope, %{letter_staves: true})

    {:ok, view, _html} = live(conn, path(version))
    assert has_element?(view, "#score .reading-aid")

    svg = conn |> get(path(version) <> "/score.svg") |> response(200)
    refute svg =~ "reading-aid"
  end
end
