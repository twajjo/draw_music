defmodule DrawMusicWeb.EditorLiveTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.AccountsFixtures
  import DrawMusic.LibraryFixtures
  import DrawMusic.MusicHelpers

  alias DrawMusic.Accounts
  alias DrawMusic.Music.{Context, Score}
  alias DrawMusicWeb.LibraryComponents

  setup :register_and_log_in_user

  # Eight bars: too many for one page-layout system.
  defp version_with_note(scope) do
    {score, id} =
      note!(Score.new(8), %Context{}, 0, "E5", %{staff: :treble, offset: 0, value: :quarter})

    {version_fixture(scope, version: %{score: score}), id}
  end

  defp path(version),
    do: LibraryComponents.version_path(version.key.composition.id, version.key, version.number)

  describe "main page" do
    test "starts a blank, unsaved composition", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#composition-name", "Untitled")
      assert has_element?(view, "#unsaved")
      assert has_element?(view, "#score")
      refute has_element?(view, "#download-svg")
      refute has_element?(view, "#score [id^='note-']")
    end

    test "sends signed-out visitors to log in" do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/")
    end
  end

  test "draws the score with its notes", %{conn: conn, scope: scope} do
    {version, note_id} = version_with_note(scope)
    {:ok, view, _html} = live(conn, path(version))

    assert has_element?(view, "#score")
    assert has_element?(view, "#note-#{note_id}")
  end

  test "shows the user's preferred layout, and the toggle switches and saves it",
       %{conn: conn, scope: scope, user: user} do
    {version, _id} = version_with_note(scope)
    {:ok, view, _html} = live(conn, path(version))

    # Strip: one system.
    refute has_element?(view, "#system-1")

    view |> element("#score-layout-page") |> render_click()
    assert has_element?(view, "#system-1")
    assert Accounts.get_user!(user.id).score_layout == :page

    view |> element("#score-layout-strip") |> render_click()
    refute has_element?(view, "#system-1")
  end

  test "someone else's version, or an unknown key, is not found", %{conn: conn, scope: scope} do
    {theirs, _id} = version_with_note(user_scope_fixture())
    assert_raise Ecto.NoResultsError, fn -> live(conn, path(theirs)) end

    {mine, _id} = version_with_note(scope)
    bad_key = String.replace(path(mine), "c-major", "h-major")
    assert_raise Ecto.NoResultsError, fn -> live(conn, bad_key) end
  end

  describe "SVG download" do
    test "is a page-layout SVG with Bravura embedded", %{conn: conn, scope: scope} do
      {version, note_id} = version_with_note(scope)
      conn = get(conn, path(version) <> "/score.svg")

      assert response_content_type(conn, :svg) =~ "image/svg+xml"
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"

      body = response(conn, 200)

      # Browsers parse image/svg+xml strictly: it must be well-formed XML.
      assert {_doc, _rest} = body |> :binary.bin_to_list() |> :xmerl_scan.string(quiet: true)

      assert body =~ "@font-face"
      assert body =~ ~s(id="note-#{note_id}")
      assert body =~ ~s(id="system-1")
    end

    test "is not available for someone else's version", %{conn: conn} do
      {theirs, _id} = version_with_note(user_scope_fixture())
      assert_error_sent 404, fn -> get(conn, path(theirs) <> "/score.svg") end
    end
  end
end
