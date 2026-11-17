defmodule DrawMusicWeb.PaperToggleTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DrawMusicWeb.{ComponentHostLive, PaperToggle}

  test "shows the paper in use", %{conn: conn} do
    view = host(conn, :black)
    assert has_element?(view, "#subject[data-paper=black]", "Sheet")
  end

  test "a click asks for the other paper", %{conn: conn} do
    view = host(conn, :white)
    view |> element("#subject") |> render_click()
    assert_receive {:component_sent, {PaperToggle, {:chosen, :black}}}

    view = host(conn, :black)
    view |> element("#subject") |> render_click()
    assert_receive {:component_sent, {PaperToggle, {:chosen, :white}}}
  end

  defp host(conn, paper) do
    attrs = %{paper: paper, id: "paper"}
    session = %{"component" => PaperToggle, "attrs" => attrs, "test_pid" => self()}
    {:ok, view, _html} = live_isolated(conn, ComponentHostLive, session: session)
    view
  end
end
