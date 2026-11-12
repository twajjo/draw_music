defmodule DrawMusicWeb.HelpLiveTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DrawMusicWeb.Shortcuts

  test "/help renders signed out with every group and the gesture diagrams" do
    {:ok, view, _html} = live(build_conn(), ~p"/help")

    for group <- Shortcuts.groups(), do: assert(has_element?(view, "h2", group))

    for diagram <- ~w(ghost-snap accidental-modifiers tie-drag rubber-band insert-shift
                      play-cursor range-playback loop) do
      assert has_element?(view, "#diagram-#{diagram}")
    end
  end

  describe "in the editor" do
    setup :register_and_log_in_user

    # Help opens and closes in the browser (JS commands), so the tests check
    # what each control runs; the server never hears about it.
    test "help is on the page, hidden; its button and ? show it, Esc and Close hide it",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#help[style*='display: none'] #help-dialog")
      assert has_element?(view, "#palette-help[phx-click*='show'][phx-click*='#help']")
      assert has_element?(view, "#help[data-show*='show'][data-show*='#help']")
      assert has_element?(view, "#help-dialog[phx-key='Escape'][phx-window-keydown*='hide']")
      assert has_element?(view, "#help-close[phx-click*='hide']")
    end

    test "it shows the current mode's shortcuts first", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#palette-mode-play") |> render_click()

      assert has_element?(view, "#help-dialog section:first-of-type > h2", "Playback")
    end

    test "the footer links to the cheat-sheet", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#footer-help[href='/help']")
    end
  end
end
