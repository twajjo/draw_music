defmodule DrawMusicWeb.LayoutToggleTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DrawMusicWeb.{ComponentHostLive, LayoutToggle}

  setup :register_and_log_in_user

  defp host(conn, scope) do
    attrs = %{scope: scope, id: "layout"}
    session = %{"component" => LayoutToggle, "attrs" => attrs, "test_pid" => self()}
    {:ok, view, _html} = live_isolated(conn, ComponentHostLive, session: session)
    view
  end

  test "shows the user's layout as chosen", %{conn: conn, scope: scope} do
    view = host(conn, scope)

    assert has_element?(view, "#subject-#{scope.user.score_layout}[aria-pressed='true']")
  end

  test "choosing a layout saves it and reports the updated user", %{conn: conn, scope: scope} do
    view = host(conn, scope)

    view |> element("#subject-page") |> render_click()
    assert_received {:component_sent, {LayoutToggle, {:updated, %{score_layout: :page}}}}

    view |> element("#subject-strip") |> render_click()
    assert_received {:component_sent, {LayoutToggle, {:updated, %{score_layout: :strip}}}}
  end
end
