defmodule DrawMusicWeb.EditorPreferencesTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusicWeb.EditorHelpers

  setup :register_and_log_in_user

  test "Preferences opens over the editor and closes back to it, unsaved work kept",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    placing_mode(view, :overlay)
    view |> element("#palette-quarter") |> render_click()
    place(view, 0, 0, "C4")

    view |> element("#account-menu-settings") |> render_click()
    assert_patch(view, "/?panel=preferences")
    assert has_element?(view, "#preferences-panel")

    view |> element("#settings-show-note-names") |> render_change(%{"value" => "false"})
    assert has_element?(view, "[data-show-note-names=false]")

    view |> element("#preferences-close") |> render_click()
    assert_patch(view, "/")
    refute has_element?(view, "#preferences-panel")
    assert notes_of(view) == [{0, 0, "C4", :quarter, 0}]
  end

  test "Manage account is its own menu item, a link to the account page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?panel=preferences")
    assert has_element?(view, ~s(#account-menu-account[href="/users/settings"]))
    refute has_element?(view, "#preferences-panel a[href='/users/settings']")
  end

  test "the panel opens from the address alone", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?panel=preferences")
    assert has_element?(view, "#preferences-panel #reading-aids")
  end
end
