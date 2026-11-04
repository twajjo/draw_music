defmodule DrawMusicWeb.CompositionDetailsTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.LibraryFixtures

  alias DrawMusic.Library
  alias DrawMusicWeb.LibraryComponents

  setup :register_and_log_in_user

  defp version_path(version),
    do: LibraryComponents.version_path(version.key.composition.id, version.key, version.number)

  defp stored(scope, version), do: Library.get_composition!(scope, version.key.composition.id)

  describe "on the compositions page" do
    test "Details changes a composition's name and credits", %{conn: conn, scope: scope} do
      version = version_fixture(scope)
      id = version.key.composition.id
      {:ok, view, _html} = live(conn, ~p"/compositions")

      view |> element("#details-#{id}") |> render_click()
      assert has_element?(view, "#details-dialog")

      view
      |> form("#details-form",
        composition: %{name: "Rhapsody", composer: "G. Gershwin", notes: "From a piano roll"}
      )
      |> render_submit()

      refute has_element?(view, "#details-dialog")
      assert has_element?(view, "#compositions", "G. Gershwin")

      assert %{name: "Rhapsody", composer: "G. Gershwin", notes: "From a piano roll"} =
               stored(scope, version)
    end

    test "a name already used is refused in the dialog", %{conn: conn, scope: scope} do
      version = version_fixture(scope)
      other = composition_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/compositions")

      view |> element("#details-#{version.key.composition.id}") |> render_click()
      view |> form("#details-form", composition: %{name: other.name}) |> render_submit()

      assert has_element?(view, "#details-dialog")
      assert stored(scope, version).name == version.key.composition.name
    end
  end

  describe "in the editor" do
    test "a saved composition's details are stored at once, not as a score change",
         %{conn: conn, scope: scope} do
      version = version_fixture(scope)
      {:ok, view, _html} = live(conn, version_path(version))

      view |> element("#edit-details") |> render_click()
      view |> form("#details-form", composition: %{subtitle: "For jazz band"}) |> render_submit()

      assert has_element?(view, "header", "For jazz band")
      assert stored(scope, version).subtitle == "For jazz band"
      refute has_element?(view, "#dirty-marker")
    end

    test "a draft keeps its details and saves with them", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#edit-details") |> render_click()

      view
      |> form("#details-form", composition: %{name: "Nocturne", composer: "J. Field"})
      |> render_submit()

      assert has_element?(view, "#composition-name", "Nocturne")
      assert Library.list_compositions(scope) == []

      view |> element("#save") |> render_click()
      assert has_element?(view, "#save-as-form input[name='composition[name]'][value='Nocturne']")

      assert has_element?(
               view,
               "#save-as-form input[name='composition[composer]'][value='J. Field']"
             )

      {:ok, _view, _html} =
        view
        |> form("#save-as-form")
        |> render_submit()
        |> follow_redirect(conn)

      assert [%{name: "Nocturne", composer: "J. Field"}] = Library.list_compositions(scope)
    end
  end
end
