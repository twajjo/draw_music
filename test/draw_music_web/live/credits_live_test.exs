defmodule DrawMusicWeb.CreditsLiveTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders signed out with every credit" do
    {:ok, view, _html} = live(build_conn(), ~p"/credits")

    for n <- 1..7, do: assert(has_element?(view, "#credit-#{n}"))
    refute has_element?(view, "#credit-8")

    assert has_element?(
             view,
             "#credit-5 a[href='https://creativecommons.org/licenses/by-sa/3.0/']",
             "CC BY-SA 3.0"
           )
  end

  test "names the author, with their email, and the help of Claude" do
    {:ok, view, _html} = live(build_conn(), ~p"/credits")

    assert has_element?(view, "#authorship", "Jeff Osborn")
    assert has_element?(view, "#author-email[href='mailto:twajjo@geekware.com']")
    assert has_element?(view, "#built-with", "Claude Opus 5.5")
  end

  describe "signed in" do
    setup :register_and_log_in_user

    test "the footer links to Credits", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#footer-credits[href='/credits']")
    end
  end
end
