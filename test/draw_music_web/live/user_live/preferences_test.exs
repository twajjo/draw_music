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

  test "changes preview and store nothing; Save stores them and leaves",
       %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/preferences")

    change(lv, %{score_layout: "page", score_paper: "black", score_ink_dark: "#ffbf47"})

    assert has_element?(lv, "#preferences-form-layout-page.btn-primary")
    assert has_element?(lv, "#preferences-form-paper-black.btn-primary")
    assert has_element?(lv, "#preferences-form-ink-ffbf47.ring-2")
    assert has_element?(lv, "#unsaved-guard[data-dirty=true]")
    assert Accounts.get_user!(user.id).score_layout == :strip

    lv |> form("#preferences-form") |> render_submit()

    stored = Accounts.get_user!(user.id)

    assert {stored.score_layout, stored.score_paper, stored.score_ink_dark} ==
             {:page, :black, "#ffbf47"}

    assert_push_event(lv, "theme:save", %{})
    assert_push_event(lv, "preferences:leave", %{to: "/compositions"})
    assert has_element?(lv, "#unsaved-guard[data-dirty=false]")
  end

  test "Cancel discards the changes and leaves", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/preferences")
    change(lv, %{letter_staves: "true"})

    lv |> element("#preferences-form-cancel") |> render_click()

    assert Accounts.get_user!(user.id).letter_staves == false
    refute_push_event(lv, "theme:save", %{})
    assert_push_event(lv, "preferences:leave", %{to: "/compositions"})
    assert has_element?(lv, "#unsaved-guard[data-dirty=false]")
  end

  test "Defaults fills in a new user's preferences, stored only on Save",
       %{conn: conn, user: user} do
    {:ok, _user} =
      Accounts.update_user_preferences(Scope.for_user(user), %{
        score_layout: :page,
        letter_staves: true,
        score_ink_dark: "#ffbf47"
      })

    {:ok, lv, _html} = live(conn, ~p"/users/preferences")
    lv |> element("#preferences-form-defaults") |> render_click()

    assert has_element?(lv, "#preferences-form-layout-strip.btn-primary")
    assert has_element?(lv, "#preferences-form-ink-ffffff.ring-2")
    assert_push_event(lv, "theme:default", %{})
    refute_push_event(lv, "theme:save", %{})
    assert Accounts.get_user!(user.id).score_layout == :page

    lv |> form("#preferences-form") |> render_submit()

    stored = Accounts.get_user!(user.id)

    assert {stored.score_layout, stored.letter_staves, stored.score_ink_dark} ==
             {:strip, false, nil}
  end

  test "names only while editing is locked while names are hidden", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/preferences")
    assert has_element?(lv, "#preferences-form-note-names-in-edit-only[checked]")
    refute has_element?(lv, "#preferences-form-note-names-in-edit-only[disabled]")

    change(lv, %{show_note_names: "false"})

    assert has_element?(lv, "#preferences-form-note-names-in-edit-only[disabled]")
  end

  test "a custom color too dark to read on black is refused, and can't be saved",
       %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/preferences")

    lv |> form("#preferences-form") |> render_change(%{custom_ink: "#202020"})

    assert has_element?(lv, "#preferences-form-ink .text-error")
    assert has_element?(lv, "#preferences-form-save[disabled]")
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

  defp change(lv, fields) do
    lv |> form("#preferences-form", user: fields) |> render_change()
  end
end
