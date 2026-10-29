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

    test "? opens the help dialog and Esc closes it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#help-dialog")

      render_hook(view, "open_help", %{})
      assert has_element?(view, "#help-dialog")

      render_hook(view, "close_help", %{})
      refute has_element?(view, "#help-dialog")
    end

    test "the toolbar's help button opens it too, in either mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#palette-mode-play") |> render_click()
      view |> element("#palette-help") |> render_click()

      assert has_element?(view, "#help-dialog")
      assert has_element?(view, "#help-dialog section:first-of-type > h2", "Playback")
    end

    test "the footer links to the cheat-sheet", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#footer-help[href='/help']")
    end
  end
end
