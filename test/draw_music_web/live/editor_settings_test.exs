defmodule DrawMusicWeb.EditorSettingsTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.LibraryFixtures
  import DrawMusicWeb.EditorHelpers

  alias DrawMusic.Library
  alias DrawMusicWeb.LibraryComponents

  setup :register_and_log_in_user

  @settings %{
    "key" => "c-major",
    "time_num" => "4",
    "time_den" => "4",
    "time_symbol" => "none",
    "tempo_bpm" => "100",
    "tempo_text" => "",
    "pickup_beats" => "0",
    "instrument" => "0"
  }

  defp apply_settings(view, changes) do
    view |> element("#settings-button") |> render_click()
    view |> form("#settings-form", settings: Map.merge(@settings, changes)) |> render_submit()
  end

  defp draft(conn) do
    {:ok, view, _html} = live(conn, ~p"/")
    placing_mode(view, :overlay)
  end

  test "a new time signature re-flows the notes into the new bars, undoably", %{conn: conn} do
    view = draft(conn)
    view |> element("#palette-half") |> render_click()
    place(view, 0, 1920, "G4")

    apply_settings(view, %{"time_num" => "3"})
    assert notes_of(view) == [{0, 1920, "G4", :quarter, 0}, {1, 0, "G4", :quarter, 0}]

    view |> element("#palette-undo") |> render_click()
    assert notes_of(view) == [{0, 1920, "G4", :half, 0}]
  end

  test "on the draft, a key change transposes in place", %{conn: conn} do
    view = draft(conn)
    view |> element("#palette-quarter") |> render_click()
    place(view, 0, 0, "C4")

    apply_settings(view, %{"key" => "g-major"})
    assert has_element?(view, "#transpose-dialog")
    view |> element("#transpose-nearest") |> render_click()

    assert notes_of(view) == [{0, 0, "G3", :quarter, 0}]
    assert session_of(view).ctx.sf == 1
    assert has_element?(view, "#dirty-marker")
  end

  test "on a saved version, a key change saves a new version in that key", %{
    conn: conn,
    scope: scope
  } do
    version = version_fixture(scope)

    {:ok, view, _html} =
      live(conn, LibraryComponents.version_path(version.key.composition.id, version.key, 1))

    apply_settings(view, %{"key" => "g-major"})

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> element("#transpose-up") |> render_click()

    assert to =~ ~r{/g-major/v/1$}
  end

  test "a pickup as long as a bar is refused", %{conn: conn} do
    view = draft(conn)
    apply_settings(view, %{"pickup_beats" => "4"})

    assert has_element?(view, "#settings-form", "must be shorter than a full measure")
    assert session_of(view).ctx.pickup_ticks == 0
  end

  test "changing only the tempo marking counts as unsaved", %{conn: conn} do
    view = draft(conn)
    apply_settings(view, %{"tempo_text" => "Adagio"})
    assert has_element?(view, "#dirty-marker")
  end

  test "the pickup bar can't be deleted", %{conn: conn} do
    view = draft(conn)
    apply_settings(view, %{"pickup_beats" => "1"})
    view |> element("#measure-0-delete") |> render_click()
    assert has_element?(view, "#flash-error", "Remove the pickup in the score settings first")
  end

  describe "instrument" do
    test "the settings form offers instruments grouped by family", %{conn: conn} do
      view = draft(conn)
      view |> element("#settings-button") |> render_click()

      assert has_element?(view, "#settings-instrument optgroup[label='Pipe']")
      assert has_element?(view, "#settings-instrument option[value='73']")
    end

    test "applying settings changes the instrument, and saving stores it",
         %{conn: conn, scope: scope} do
      version = version_fixture(scope)

      {:ok, view, _html} =
        live(conn, LibraryComponents.version_path(version.key.composition.id, version.key, 1))

      apply_settings(view, %{"instrument" => "73"})
      assert has_element?(view, "#dirty-marker")
      view |> element("#save") |> render_click()

      assert Library.get_version!(scope, version.id).instrument == 73
    end

    test "an instrument outside 0..127 is refused", %{conn: conn} do
      view = draft(conn)
      view |> element("#settings-button") |> render_click()

      render_hook(view, "apply_settings", %{"settings" => Map.put(@settings, "instrument", "128")})

      assert has_element?(view, "#settings-form", "must be less than or equal to 127")
      assert :sys.get_state(view.pid).socket.assigns.instrument == 0
    end

    test "the hook is told the instrument", %{conn: conn} do
      view = draft(conn)
      apply_settings(view, %{"instrument" => "73"})

      assert has_element?(view, ~s(#score-editor[data-instrument*='"program":73']))
    end
  end

  test "a tempo change is saved with the version", %{conn: conn, scope: scope} do
    version = version_fixture(scope)

    {:ok, view, _html} =
      live(conn, LibraryComponents.version_path(version.key.composition.id, version.key, 1))

    apply_settings(view, %{"tempo_bpm" => "90", "tempo_text" => "Andante"})
    view |> element("#save") |> render_click()

    saved = Library.get_version!(scope, version.id)
    assert {saved.tempo_bpm, saved.tempo_text} == {90, "Andante"}
  end
end
