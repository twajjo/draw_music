defmodule DrawMusicWeb.EditorPreferencesTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusicWeb.EditorHelpers

  alias DrawMusic.Accounts

  setup :register_and_log_in_user

  test "the panel previews over the editor; Cancel puts the stored ones back, work kept",
       %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/")
    placing_mode(view, :overlay)
    view |> element("#palette-quarter") |> render_click()
    place(view, 0, 0, "C4")

    view |> element("#account-menu-settings") |> render_click()
    assert_patch(view, "/?panel=preferences")
    assert has_element?(view, "#preferences-panel")

    change(view, %{show_note_names: "false"})
    assert has_element?(view, "[data-show-note-names=false]")
    assert Accounts.get_user!(user.id).show_note_names == true

    view |> element("#preferences-form-cancel") |> render_click()
    assert_patch(view, "/")
    refute has_element?(view, "#preferences-panel")
    assert has_element?(view, "[data-show-note-names=true]")
    assert notes_of(view) == [{0, 0, "C4", :quarter, 0}]
  end

  test "Save stores the preferences and closes the panel", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/?panel=preferences")
    change(view, %{letter_staves: "true"})

    view |> form("#preferences-form") |> render_submit()

    assert_patch(view, "/")
    assert Accounts.get_user!(user.id).letter_staves == true
    assert has_element?(view, "#score .reading-aid")
  end

  test "only Save or Cancel leaves the panel; Back drops the preview", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?panel=preferences")
    refute has_element?(view, "#preferences-close")
    refute has_element?(view, "#preferences-panel[phx-click-away]")
    refute has_element?(view, "#preferences-panel[phx-window-keydown]")

    change(view, %{letter_staves: "true"})
    assert has_element?(view, "#score .reading-aid")

    render_patch(view, "/")
    refute has_element?(view, "#score .reading-aid")
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

  test "the theme is chosen in the form only, not the account menu", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?panel=preferences")

    for theme <- ~w(system light dark) do
      assert has_element?(view, "#preferences-form #preferences-form-theme-#{theme}")
    end

    refute has_element?(view, "#account-menu [data-phx-theme]")
  end

  defp change(view, fields) do
    view |> form("#preferences-form", user: fields) |> render_change()
  end
end
