defmodule DrawMusicWeb.LibraryLiveTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.AccountsFixtures
  import DrawMusic.LibraryFixtures

  alias DrawMusic.Library

  setup :register_and_log_in_user

  describe "library" do
    test "lists the user's own compositions only", %{conn: conn, scope: scope} do
      mine = version_fixture(scope)
      theirs = version_fixture(user_scope_fixture())

      {:ok, view, _html} = live(conn, ~p"/compositions")

      assert has_element?(view, "#version-#{mine.id}")
      refute has_element?(view, "#version-#{theirs.id}")
    end

    test "each version has an edit button naming its key, and a delete button that asks first",
         %{conn: conn, scope: scope} do
      version = version_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/compositions")

      assert has_element?(view, "#version-#{version.id}", "C major · v1")
      assert has_element?(view, "#delete-version-#{version.id}[data-confirm]")
    end

    test "deleting one key's version keeps the composition's others", %{conn: conn, scope: scope} do
      c_major = version_fixture(scope)
      composition = c_major.key.composition

      {:ok, d_minor} =
        Library.save_in_key(
          scope,
          composition,
          key_attrs(%{sf: -1, mode: :minor}),
          version_attrs()
        )

      {:ok, view, _html} = live(conn, ~p"/compositions")

      view |> element("#delete-version-#{c_major.id}") |> render_click()

      refute has_element?(view, "#version-#{c_major.id}")
      assert has_element?(view, "#version-#{d_minor.id}", "D minor · v1")
    end

    test "deleting a composition's only version deletes the composition",
         %{conn: conn, scope: scope} do
      version = version_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/compositions")

      view |> element("#delete-version-#{version.id}") |> render_click()

      refute has_element?(view, "#version-#{version.id}")
      assert Library.list_compositions(scope) == []
    end

    test "requires signing in" do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/compositions")
    end
  end

  describe "new composition" do
    test "creates version 1 and opens it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/compositions/new")

      {:ok, score_view, _html} =
        view
        |> form("#composition-form",
          composition: %{name: "Minuet", key: "g-major", time_num: "3", time_den: "4"}
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert has_element?(score_view, "#composition-name", "Minuet")
      assert has_element?(score_view, "#score")
    end

    test "shows errors and stays put for an invalid composition", %{conn: conn, scope: scope} do
      taken = composition_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/compositions/new")

      # A pickup as long as a whole bar.
      view
      |> form("#composition-form", composition: %{name: "Gavotte", pickup_beats: "4"})
      |> render_submit()

      assert has_element?(view, "#composition-form .text-error")

      view
      |> form("#composition-form", composition: %{name: taken.name, pickup_beats: "0"})
      |> render_submit()

      assert has_element?(view, "#composition-form .text-error")
    end
  end
end
