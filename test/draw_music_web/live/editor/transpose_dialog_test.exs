defmodule DrawMusicWeb.Editor.TransposeDialogTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DrawMusicWeb.ComponentHostLive
  alias DrawMusicWeb.Editor.TransposeDialog

  setup :register_and_log_in_user

  defp host(conn, attrs) do
    session = %{"component" => TransposeDialog, "attrs" => attrs, "test_pid" => self()}
    {:ok, view, _html} = live_isolated(conn, ComponentHostLive, session: session)
    view
  end

  setup %{conn: conn} do
    %{view: host(conn, %{key: {1, :major}})}
  end

  test "names the chosen key", %{view: view} do
    assert has_element?(view, "#transpose-dialog h2", "G major")
  end

  for {id, direction} <- [nearest: :nearest, up: :up, down: :down] do
    test "#{id} reports the key and the direction", %{view: view} do
      view |> element("#transpose-#{unquote(id)}") |> render_click()

      assert_received {:component_sent, {:editor, {:transpose, {1, :major}, unquote(direction)}}}
    end
  end

  test "Cancel reports close", %{view: view} do
    view |> element("#transpose-cancel") |> render_click()

    assert_received {:component_sent, {:editor, :close}}
  end

  test "needs a key", %{conn: conn} do
    assert_raise ArgumentError, "TransposeDialog needs a :key", fn ->
      host(conn, %{key: :none})
    end
  end
end
