defmodule DrawMusicWeb.EditorKeySuggestionTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusicWeb.EditorHelpers

  import DrawMusic.LibraryFixtures

  alias DrawMusic.Music.Pitch
  alias DrawMusicWeb.LibraryComponents

  setup :register_and_log_in_user

  # E♭ major entered by ear into the new piece's C major: every E♭, A♭ and
  # B♭ written sharp.
  @by_ear [
    ~w(D#4 F4 G4 G#4),
    ~w(A#4 C5 D5 D#5),
    ~w(D#4 G4 A#4 D#5),
    ~w(G#4 G4 F4 D#4)
  ]

  defp enter_by_ear(view) do
    placing_mode(view, :overlay)
    view |> element("#palette-quarter") |> render_click()

    for {bar, measure} <- Enum.with_index(@by_ear), {spn, beat} <- Enum.with_index(bar) do
      place(view, measure, beat * 960, spn, alter: true)
    end
  end

  defp e_flat_choice, do: "#palette-key--3-major"

  test "Suggest key stays off while the notes suit their key", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#palette-suggest-key[aria-disabled=true]")
    refute has_element?(view, "#palette-key-menu button")
  end

  test "it offers E♭ for notes heard in E♭, and re-keys them unchanged in sound",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    enter_by_ear(view)
    before = session_of(view).score

    assert has_element?(view, "#palette-suggest-key[aria-disabled=false]")
    # Its relative minor shares the key signature, so it's offered too.
    assert has_element?(view, "#palette-key--3-minor")
    view |> element(e_flat_choice()) |> render_click()

    session = session_of(view)
    assert {session.ctx.sf, session.ctx.mode} == {-3, :major}
    assert {0, 0, "E♭4", :quarter, 0} in notes_of(view)
    assert {1, 0, "B♭4", :quarter, 0} in notes_of(view)
    assert has_element?(view, "#palette-suggest-key[aria-disabled=true]")

    sounding = fn score ->
      for m <- score.measures, n <- m.notes, do: Pitch.midi(n.step, n.alter)
    end

    assert sounding.(session.score) == sounding.(before)

    view |> element("#palette-undo") |> render_click()
    assert session_of(view).ctx.sf == 0
    assert session_of(view).score == before
  end

  test "a saved piece re-keyed is saved in the new key, saying the old one is kept",
       %{conn: conn, scope: scope} do
    version = version_fixture(scope)
    path = LibraryComponents.version_path(version.key.composition.id, version.key, version.number)
    {:ok, view, _html} = live(conn, path)

    send(view.pid, {:editor, {:rekey, {-3, :major}}})

    {to, flash} = assert_redirect(view)
    assert to =~ "/e-flat-major/v/1"
    assert flash["info"] == "Saved as E♭ major v1 (C major v1 is kept)"
  end
end
