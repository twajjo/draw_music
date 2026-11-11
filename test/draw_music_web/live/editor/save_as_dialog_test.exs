defmodule DrawMusicWeb.Editor.SaveAsDialogTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.LibraryFixtures

  alias DrawMusic.Library
  alias DrawMusic.Library.{Composition, Key, Version}
  alias DrawMusic.Music.Score
  alias DrawMusicWeb.ComponentHostLive
  alias DrawMusicWeb.Editor.SaveAsDialog

  setup :register_and_log_in_user

  defp host(conn, attrs) do
    session = %{"component" => SaveAsDialog, "attrs" => attrs, "test_pid" => self()}
    {:ok, view, _html} = live_isolated(conn, ComponentHostLive, session: session)
    view
  end

  # A draft that was given a name and a composer in its details.
  setup %{conn: conn, scope: scope} do
    composition = %Composition{name: "Nocturne", composer: "J. Field", keys: []}

    version = %Version{
      key: %Key{sf: 0, mode: :major, composition: composition},
      score: Score.new(4)
    }

    attrs = %{
      scope: scope,
      composition: composition,
      version: version,
      key: %{sf: 2, mode: :major},
      version_attrs: version_attrs()
    }

    %{view: host(conn, attrs)}
  end

  test "starts from the draft's name and credits", %{view: view} do
    assert has_element?(view, "#save-as-form input[name='composition[name]'][value='Nocturne']")

    assert has_element?(
             view,
             "#save-as-form input[name='composition[composer]'][value='J. Field']"
           )
  end

  test "shows a missing name while typing", %{view: view} do
    view |> form("#save-as-form", composition: %{name: ""}) |> render_change()

    assert has_element?(view, "#save-as-form", "can't be blank")
    refute_received {:component_sent, _message}
  end

  test "saving creates the composition in the key and reports its first version",
       %{view: view, scope: scope} do
    view |> form("#save-as-form") |> render_submit()

    assert_received {:component_sent, {:editor, {:saved, %Version{number: 1} = saved, "Saved"}}}
    assert saved.key.sf == 2
    assert Library.get_composition_by_name(scope, "Nocturne")
  end

  test "a name already taken stays in the form and reports nothing",
       %{view: view, scope: scope} do
    taken = composition_fixture(scope)

    view |> form("#save-as-form", composition: %{name: taken.name}) |> render_submit()

    assert has_element?(view, "#save-as-form", "you already have a composition with this name")
    refute_received {:component_sent, _message}
  end

  test "Cancel reports close", %{view: view} do
    view |> element("#save-as-form button", "Cancel") |> render_click()

    assert_received {:component_sent, {:editor, :close}}
  end

  test "needs its inputs", %{conn: conn, scope: scope} do
    assert_raise ArgumentError, ~r/SaveAsDialog needs/, fn ->
      host(conn, %{scope: scope})
    end
  end
end
