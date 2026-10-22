defmodule DrawMusicWeb.EditorSaveTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.LibraryFixtures
  import DrawMusicWeb.EditorHelpers

  alias DrawMusic.{Library, MusicHelpers}
  alias DrawMusicWeb.LibraryComponents

  setup :register_and_log_in_user

  defp open(conn, version) do
    {:ok, view, _html} =
      live(
        conn,
        LibraryComponents.version_path(version.key.composition.id, version.key, version.number)
      )

    view
  end

  defp add_note(view) do
    view |> element("#palette-quarter") |> render_click()
    place(view, 0, 0, "C4")
  end

  describe "a saved version" do
    setup %{conn: conn, scope: scope} do
      version = version_fixture(scope)
      %{version: version, view: open(conn, version)}
    end

    test "Save stores the score and clears the unsaved marker", %{
      view: view,
      scope: scope,
      version: version
    } do
      refute has_element?(view, "#dirty-marker")
      add_note(view)
      assert has_element?(view, "#dirty-marker")

      view |> element("#save") |> render_click()

      refute has_element?(view, "#dirty-marker")
      saved = Library.get_version!(scope, version.id)
      assert [{0, 0, "C4", :quarter, 0}] = MusicHelpers.notes(saved.score)
    end

    test "Save as new version stores the next version and opens it", %{view: view} do
      add_note(view)

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> element("#save-new-version") |> render_click()

      assert to =~ ~r{/v/2$}
    end
  end

  describe "the draft" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      %{view: view}
    end

    test "has no Save as new version", %{view: view} do
      refute has_element?(view, "#save-new-version")
    end

    test "Save asks for a name, then creates the composition and opens it", %{
      view: view,
      scope: scope
    } do
      add_note(view)
      view |> element("#save") |> render_click()
      assert has_element?(view, "#save-as-form")

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> form("#save-as-form", composition: %{name: "Etude"}) |> render_submit()

      assert to =~ ~r{/c-major/v/1$}
      composition = Library.get_composition_by_name(scope, "Etude")
      assert composition
    end

    test "a name already taken is reported in the form", %{view: view, scope: scope} do
      taken = composition_fixture(scope)
      view |> element("#save") |> render_click()

      view |> form("#save-as-form", composition: %{name: taken.name}) |> render_submit()

      assert has_element?(view, "#save-as-form", "you already have a composition with this name")
    end
  end

  test "the score editor carries the unsaved flag for the leave guard", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#score-editor[data-dirty=false]")
    add_note(view)
    assert has_element?(view, "#score-editor[data-dirty=true]")
  end
end
