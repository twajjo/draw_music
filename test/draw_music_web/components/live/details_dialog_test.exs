defmodule DrawMusicWeb.DetailsDialogTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.LibraryFixtures

  alias DrawMusicWeb.{ComponentHostLive, DetailsDialog}

  setup :register_and_log_in_user

  defp host(conn, attrs) do
    session = %{"component" => DetailsDialog, "attrs" => attrs, "test_pid" => self()}
    {:ok, view, _html} = live_isolated(conn, ComponentHostLive, session: session)
    view
  end

  setup %{scope: scope} do
    %{composition: composition_fixture(scope)}
  end

  test "opens on the composition's details", %{conn: conn, scope: scope, composition: c} do
    view = host(conn, %{scope: scope, composition: c})

    assert has_element?(view, "#details-form input[name='composition[name]'][value='#{c.name}']")
  end

  test "shows a missing name while typing", %{conn: conn, scope: scope, composition: c} do
    view = host(conn, %{scope: scope, composition: c})

    view |> form("#details-form", composition: %{name: ""}) |> render_change()

    assert has_element?(view, "#details-form", "can't be blank")
    refute_received {:component_sent, _message}
  end

  test "saving reports the changed composition", %{conn: conn, scope: scope, composition: c} do
    view = host(conn, %{scope: scope, composition: c})

    view |> form("#details-form", composition: %{composer: "J. Field"}) |> render_submit()

    assert_received {:component_sent, {DetailsDialog, {:saved, %{composer: "J. Field"}}}}
  end

  test "a draft's details are checked and reported, not stored",
       %{conn: conn, scope: scope, composition: c} do
    view = host(conn, %{scope: scope, composition: c, persist?: false})

    view |> form("#details-form", composition: %{name: "Nocturne"}) |> render_submit()

    assert_received {:component_sent, {DetailsDialog, {:saved, %{name: "Nocturne", id: id}}}}
    assert id == c.id
  end

  test "a refused save keeps the dialog open and reports nothing",
       %{conn: conn, scope: scope, composition: c} do
    view = host(conn, %{scope: scope, composition: c})

    view |> form("#details-form", composition: %{name: ""}) |> render_submit()

    assert has_element?(view, "#details-dialog")
    refute_received {:component_sent, _message}
  end

  test "Cancel and Esc report that it closed", %{conn: conn, scope: scope, composition: c} do
    view = host(conn, %{scope: scope, composition: c})

    view |> element("#details-dialog button", "Cancel") |> render_click()
    assert_received {:component_sent, {DetailsDialog, :closed}}

    view |> element("#details-dialog") |> render_keydown(%{"key" => "Escape"})
    assert_received {:component_sent, {DetailsDialog, :closed}}
  end
end
