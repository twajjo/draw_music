defmodule DrawMusicWeb.ImportDialogTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.LibraryFixtures

  alias DrawMusic.Library.{Composition, Key, Version}
  alias DrawMusic.MidiCodec
  alias DrawMusic.Music.Score
  alias DrawMusicWeb.{ComponentHostLive, ImportDialog}

  setup :register_and_log_in_user

  defp host(conn, attrs) do
    session = %{"component" => ImportDialog, "attrs" => attrs, "test_pid" => self()}
    {:ok, view, _html} = live_isolated(conn, ComponentHostLive, session: session)
    view
  end

  # A .mid file as this app exports it, named by its track name.
  defp midi(name) do
    key = %Key{sf: 0, mode: :major, composition: %Composition{name: name}}
    version = %Version{number: 1, key: key, time_num: 4, time_den: 4, score: Score.new(1)}
    {:ok, binary} = MidiCodec.export(version)
    binary
  end

  defp upload(view, content) do
    file = file_input(view, "#import-form", :midi, [%{name: "song.mid", content: content}])
    render_upload(file, "song.mid")
    view |> form("#import-form") |> render_submit()
    view
  end

  defp name_it(view, name) do
    view |> form("#import-name-form", import: %{name: name}) |> render_submit()
    view
  end

  test "the file's track name fills the name form", %{conn: conn, scope: scope} do
    view = conn |> host(%{scope: scope}) |> upload(midi("Waltz"))

    assert has_element?(view, "#import-name-form input[value='Waltz']")
  end

  test "an unreadable file says so and reports nothing", %{conn: conn, scope: scope} do
    view = conn |> host(%{scope: scope}) |> upload("not a midi file")

    assert has_element?(view, "#import-error")
    refute has_element?(view, "#import-name-form")
    refute_received {:component_sent, _message}
  end

  test "a blank name is refused", %{conn: conn, scope: scope} do
    view = conn |> host(%{scope: scope}) |> upload(midi("Waltz")) |> name_it("  ")

    assert has_element?(view, "#import-name-form", "can't be blank")
    refute_received {:component_sent, _message}
  end

  test "a new name reports the imported version", %{conn: conn, scope: scope} do
    conn |> host(%{scope: scope}) |> upload(midi("Waltz")) |> name_it("Evening Waltz")

    assert_received {:component_sent, {ImportDialog, {:imported, %Version{number: 1}}}}
  end

  describe "a name already in the library" do
    setup %{conn: conn, scope: scope} do
      version_fixture(scope, composition: %{name: "Waltz"})
      view = conn |> host(%{scope: scope}) |> upload(midi("Waltz")) |> name_it("Waltz")
      %{view: view}
    end

    test "asks what to do", %{view: view} do
      assert has_element?(view, "#import-collision")
      refute_received {:component_sent, _message}
    end

    test "Replace reports version 1", %{view: view} do
      view |> element("#import-replace") |> render_click()

      assert_received {:component_sent, {ImportDialog, {:imported, %Version{number: 1}}}}
    end

    test "New version reports the next version", %{view: view} do
      view |> element("#import-new-version") |> render_click()

      assert_received {:component_sent, {ImportDialog, {:imported, %Version{number: 2}}}}
    end

    test "a different name goes back to the name form", %{view: view} do
      view |> element("#import-rename") |> render_click()

      assert has_element?(view, "#import-name-form", "is already in your library")
    end

    test "Cancel reports closed", %{view: view} do
      view |> element("#import-cancel") |> render_click()

      assert_received {:component_sent, {ImportDialog, :closed}}
    end
  end

  test "needs a scope", %{conn: conn} do
    assert_raise ArgumentError, "ImportDialog needs a :scope", fn ->
      host(conn, %{})
    end
  end
end
