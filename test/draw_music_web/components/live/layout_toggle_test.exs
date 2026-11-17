defmodule DrawMusicWeb.LayoutToggleTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DrawMusicWeb.{ComponentHostLive, LayoutToggle}

  test "shows the given layout as chosen", %{conn: conn} do
    view = host(conn, :page)

    assert has_element?(view, "#subject-page[aria-pressed='true']")
    assert has_element?(view, "#subject-strip[aria-pressed='false']")
  end

  test "choosing the other layout reports it", %{conn: conn} do
    view = host(conn, :strip)

    view |> element("#subject-page") |> render_click()
    assert_receive {:component_sent, {LayoutToggle, {:chosen, :page}}}
  end

  defp host(conn, layout) do
    attrs = %{layout: layout, id: "layout"}
    session = %{"component" => LayoutToggle, "attrs" => attrs, "test_pid" => self()}
    {:ok, view, _html} = live_isolated(conn, ComponentHostLive, session: session)
    view
  end
end
