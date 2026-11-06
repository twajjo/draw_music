defmodule DrawMusicWeb.InkPickerTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DrawMusicWeb.{ComponentHostLive, InkPicker}

  setup :register_and_log_in_user

  defp host(conn, scope) do
    session = %{"component" => InkPicker, "attrs" => %{scope: scope}, "test_pid" => self()}
    {:ok, view, _html} = live_isolated(conn, ComponentHostLive, session: session)
    view
  end

  test "with no color saved, white is chosen", %{conn: conn, scope: scope} do
    view = host(conn, scope)

    assert has_element?(view, "#subject-ffffff[aria-pressed='true']")
  end

  test "a swatch saves its color and reports the updated user", %{conn: conn, scope: scope} do
    view = host(conn, scope)

    view |> element("#subject-ffbf47") |> render_click()

    assert_received {:component_sent, {InkPicker, {:updated, %{score_ink_dark: "#ffbf47"}}}}
  end

  test "a custom color too dark to read is refused, with the reason shown",
       %{conn: conn, scope: scope} do
    view = host(conn, scope)

    view |> form("#subject-custom", %{color: "#202020"}) |> render_submit()

    assert has_element?(view, "#subject .text-error")
    refute_received {:component_sent, _message}
  end

  test "a readable custom color is saved and clears the error", %{conn: conn, scope: scope} do
    view = host(conn, scope)

    view |> form("#subject-custom", %{color: "#202020"}) |> render_submit()
    view |> form("#subject-custom", %{color: "#c0ffee"}) |> render_submit()

    refute has_element?(view, "#subject .text-error")
    assert_received {:component_sent, {InkPicker, {:updated, %{score_ink_dark: "#c0ffee"}}}}
  end
end
