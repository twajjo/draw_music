defmodule DrawMusicWeb.UserLive.PreferencesTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.AccountsFixtures

  alias DrawMusic.Accounts
  alias DrawMusic.Accounts.Scope

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "a swatch saves the dark-mode ink and the layout toggle saves the layout",
       %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/preferences")

    lv |> element("#settings-ink-ffbf47") |> render_click()
    lv |> element("#settings-layout-page") |> render_click()

    user = Accounts.get_user!(user.id)
    assert user.score_ink_dark == "#ffbf47"
    assert user.score_layout == :page
  end

  test "naming the note being placed or moved is on until turned off",
       %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/preferences")
    assert has_element?(lv, "#settings-show-note-names-input[checked]")

    lv |> element("#settings-show-note-names") |> render_change(%{"value" => "false"})

    assert Accounts.get_user!(user.id).show_note_names == false
    refute has_element?(lv, "#settings-show-note-names-input[checked]")
  end

  test "names only while editing is on, and locked while names are hidden",
       %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/preferences")
    assert has_element?(lv, "#settings-note-names-in-edit-only-input[checked]")
    refute has_element?(lv, "#settings-note-names-in-edit-only-input[disabled]")

    lv |> element("#settings-show-note-names") |> render_change(%{"value" => "false"})
    assert has_element?(lv, "#settings-note-names-in-edit-only-input[disabled]")

    scope = Scope.for_user(Accounts.get_user!(user.id))

    assert {:error, _changeset} =
             Accounts.update_user_preferences(scope, %{note_names_in_edit_only: false})
  end

  test "a custom color too dark to read on black is refused", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/preferences")

    lv |> form("#settings-ink-custom", %{color: "#202020"}) |> render_submit()

    assert has_element?(lv, "#settings-ink .text-error")
    assert Accounts.get_user!(user.id).score_ink_dark == nil
  end

  test "the account menu leads here, and to the account page apart", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/preferences")

    assert has_element?(lv, ~s(#account-menu-settings[href="/users/preferences"]), "Preferences")
    assert has_element?(lv, ~s(#account-menu-account[href="/users/settings"]))
    refute has_element?(lv, "#email_form")
  end

  test "needs no recent log-in, unlike the account page", %{conn: conn} do
    stale = DateTime.add(DateTime.utc_now(:second), -11, :minute)
    conn = log_in_user(conn, user_fixture(), token_authenticated_at: stale)

    assert {:ok, _lv, _html} = live(conn, ~p"/users/preferences")
  end
end
