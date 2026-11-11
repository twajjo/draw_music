defmodule DrawMusicWeb.Editor.SaveMenuTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.LibraryFixtures

  alias DrawMusic.Library
  alias DrawMusic.Library.{Key, Version}
  alias DrawMusic.Music.Score
  alias DrawMusicWeb.ComponentHostLive
  alias DrawMusicWeb.Editor.SaveMenu

  setup :register_and_log_in_user

  defp host(conn, attrs) do
    session = %{"component" => SaveMenu, "attrs" => attrs, "test_pid" => self()}
    {:ok, view, _html} = live_isolated(conn, ComponentHostLive, session: session)
    view
  end

  defp draft, do: %Version{key: %Key{sf: 0, mode: :major}, score: Score.new(4)}

  test "shows the unsaved-changes dot only when there are changes",
       %{conn: conn, scope: scope} do
    clean = host(conn, %{scope: scope, version: draft(), version_attrs: version_attrs()})
    refute has_element?(clean, "#dirty-marker")

    dirty =
      host(conn, %{scope: scope, version: draft(), version_attrs: version_attrs(), dirty?: true})

    assert has_element?(dirty, "#dirty-marker")
  end

  describe "the draft" do
    setup %{conn: conn, scope: scope} do
      %{view: host(conn, %{scope: scope, version: draft(), version_attrs: version_attrs()})}
    end

    test "has no Save as new version", %{view: view} do
      refute has_element?(view, "#save-new-version")
    end

    test "Save asks for a new composition", %{view: view} do
      view |> element("#save") |> render_click()

      assert_received {:component_sent, {:editor, {:open, :save_as}}}
    end
  end

  describe "a stored version" do
    setup %{conn: conn, scope: scope} do
      version = version_fixture(scope)
      attrs = version_attrs(%{tempo_bpm: 90})

      %{
        version: version,
        view: host(conn, %{scope: scope, version: version, version_attrs: attrs})
      }
    end

    test "Save stores it and reports the same version", %{view: view, scope: scope, version: v} do
      view |> element("#save") |> render_click()

      assert_received {:component_sent, {:editor, {:saved, %Version{id: id}, "Saved"}}}
      assert id == v.id
      assert Library.get_version!(scope, v.id).tempo_bpm == 90
    end

    test "Save as new version reports the next version", %{view: view} do
      view |> element("#save-new-version") |> render_click()

      assert_received {:component_sent,
                       {:editor, {:saved, %Version{number: 2}, "Saved as version 2"}}}
    end

    test "Save as new composition asks for one", %{view: view} do
      view |> element("#save-as") |> render_click()

      assert_received {:component_sent, {:editor, {:open, :save_as}}}
    end
  end

  test "a refused save is reported as an error", %{conn: conn, scope: scope} do
    version = version_fixture(scope)
    attrs = version_attrs(%{time_den: 3})
    view = host(conn, %{scope: scope, version: version, version_attrs: attrs})

    view |> element("#save") |> render_click()

    assert_received {:component_sent, {:editor, {:flash, :error, "Couldn't save" <> _rest}}}
  end

  test "needs its inputs", %{conn: conn, scope: scope} do
    assert_raise ArgumentError, ~r/SaveMenu needs/, fn ->
      host(conn, %{scope: scope})
    end
  end
end
