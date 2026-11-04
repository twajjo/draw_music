defmodule DrawMusicWeb.LibraryImportTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.LibraryFixtures

  alias DrawMusic.{Library, MidiCodec}
  alias DrawMusic.Library.{Composition, Key, Version}
  alias DrawMusic.Music.Score

  setup :register_and_log_in_user

  # A .mid file as this app exports it, named by its track name.
  defp midi(name) do
    key = %Key{sf: 0, mode: :major, composition: %Composition{name: name}}
    version = %Version{number: 1, key: key, time_num: 4, time_den: 4, score: Score.new(1)}
    {:ok, binary} = MidiCodec.export(version)
    binary
  end

  defp upload(view, filename, content) do
    view |> element("#import-open") |> render_click()
    file = file_input(view, "#import-form", :midi, [%{name: filename, content: content}])
    render_upload(file, filename)
    view |> form("#import-form") |> render_submit()
  end

  defp name_it(view, name) do
    view |> form("#import-name-form", import: %{name: name}) |> render_submit()
  end

  defp opened({:error, {:live_redirect, %{to: to}}}), do: to

  defp versions(scope, name) do
    composition = Library.get_composition_by_name(scope, name)
    composition = Library.get_composition!(scope, composition.id)
    for key <- composition.keys, version <- key.versions, do: {Key.name(key), version.number}
  end

  test "names the piece from the file, takes an edited name, and opens it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/compositions")
    upload(view, "song.mid", midi("Waltz"))

    assert has_element?(view, "#import-name-form input[value='Waltz']")

    {:ok, editor, _html} =
      view
      |> name_it("Evening Waltz")
      |> follow_redirect(conn)

    assert has_element?(editor, "#composition-name", "Evening Waltz")
  end

  test "an unreadable file says so and imports nothing", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/compositions")
    upload(view, "notes.mid", "not a midi file")

    assert has_element?(view, "#import-error")
    refute has_element?(view, "#import-name-form")
    assert Library.list_compositions(scope) == []
  end

  describe "a name already in the library" do
    setup %{scope: scope} do
      version = version_fixture(scope, composition: %{name: "Waltz"})
      {:ok, _v2} = Library.save_new_version(scope, version.key, version_attrs())
      :ok
    end

    defp collide(conn) do
      {:ok, view, _html} = live(conn, ~p"/compositions")
      upload(view, "song.mid", midi("Waltz"))
      name_it(view, "Waltz")
      assert has_element?(view, "#import-collision")
      view
    end

    test "Replace stores it as version 1 of that key", %{conn: conn, scope: scope} do
      view = collide(conn)
      to = view |> element("#import-replace") |> render_click() |> opened()

      assert to =~ "/c-major/v/1"
      assert versions(scope, "Waltz") == [{"C major", 1}]
    end

    test "New version adds the next version in that key", %{conn: conn, scope: scope} do
      view = collide(conn)
      to = view |> element("#import-new-version") |> render_click() |> opened()

      assert to =~ "/c-major/v/3"
      assert versions(scope, "Waltz") == [{"C major", 1}, {"C major", 2}, {"C major", 3}]
    end

    test "a different name is checked again", %{conn: conn, scope: scope} do
      view = collide(conn)
      view |> element("#import-rename") |> render_click()

      assert has_element?(view, "#import-name-form")
      name_it(view, "Waltz")
      assert has_element?(view, "#import-collision")

      view |> element("#import-rename") |> render_click()
      to = view |> name_it("Second Waltz") |> opened()

      assert to =~ "/c-major/v/1"
      assert versions(scope, "Second Waltz") == [{"C major", 1}]
    end

    test "Cancel closes the dialog and changes nothing", %{conn: conn, scope: scope} do
      view = collide(conn)
      view |> element("#import-cancel") |> render_click()

      refute has_element?(view, "#import-collision")
      assert versions(scope, "Waltz") == [{"C major", 1}, {"C major", 2}]
    end
  end
end
