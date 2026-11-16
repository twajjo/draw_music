defmodule DrawMusicWeb.EditorPlaceTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusic.LibraryFixtures
  import DrawMusicWeb.EditorHelpers

  alias DrawMusicWeb.LibraryComponents

  setup :register_and_log_in_user

  # Most tests place at exact positions, so they work in Overlay.
  defp draft(conn, mode \\ :overlay) do
    {:ok, view, _html} = live(conn, ~p"/")
    placing_mode(view, mode)
  end

  defp arm(view, value), do: view |> element("#palette-#{value}") |> render_click()

  test "a placed note appears", %{conn: conn} do
    view = draft(conn)
    arm(view, "eighth")
    place(view, 0, 480, "G4")

    assert notes_of(view) == [{0, 480, "G4", :eighth, 0}]
    assert count(view, "#score [id^='note-']") == 1
  end

  test "the picked item stays armed for further placements until another is picked",
       %{conn: conn} do
    view = draft(conn)
    arm(view, "quarter")
    place(view, 0, 0, "C4")
    place(view, 0, 960, "D4")

    assert length(notes_of(view)) == 2
    assert has_element?(view, "#palette-quarter[aria-pressed=true]")

    arm(view, "eighth")
    assert has_element?(view, "#palette-eighth[aria-pressed=true]")
    refute has_element?(view, "#palette-quarter[aria-pressed=true]")
  end

  test "the key signature supplies the accidental unless one is given", %{
    conn: conn,
    scope: scope
  } do
    version = version_fixture(scope, key: %{sf: 2})

    {:ok, view, _html} =
      live(conn, LibraryComponents.version_path(version.key.composition.id, version.key, 1))

    view |> element("#palette") |> render_hook("arm", %{"kind" => "note", "value" => "quarter"})
    place(view, 0, 0, "F4")
    place(view, 0, 960, "F4", alter: true)

    assert [{0, 0, "F♯4", :quarter, 0}, {0, 960, "F4", :quarter, 0}] = notes_of(view)
  end

  test "a refused placement explains why and keeps the item armed", %{conn: conn} do
    view = draft(conn)
    arm(view, "half")
    place(view, 0, 0, "C#8", alter: true)

    assert has_element?(view, "#flash-error", "outside the piano's range")
    assert has_element?(view, "#palette-half[aria-pressed=true]")
    assert notes_of(view) == []
  end

  test "a click on a bar that no longer exists is refused", %{conn: conn} do
    view = draft(conn)
    arm(view, "quarter")
    place(view, 99, 0, "C4")

    assert has_element?(view, "#flash-error", "That bar no longer exists")
  end

  test "forged placement params are ignored", %{conn: conn} do
    view = draft(conn)
    arm(view, "quarter")

    for bad <- [
          %{"measure" => 0, "offset" => 0, "staff" => "alto", "step" => 28},
          %{"measure" => 0, "offset" => 0, "staff" => "treble", "step" => "x"},
          %{"measure" => 0, "offset" => 0, "staff" => "treble", "step" => 28, "alter" => 9},
          %{"measure" => -1, "offset" => 0, "staff" => "treble", "step" => 28}
        ] do
      canvas_hook(view, "place", bad)
    end

    assert notes_of(view) == []
    assert has_element?(view, "#palette-quarter[aria-pressed=true]")
  end

  test "Insert mode moves later music on that staff right", %{conn: conn} do
    view = draft(conn)
    arm(view, "quarter")
    place(view, 0, 0, "C4")
    arm(view, "whole")
    place(view, 0, 0, "C3", staff: "bass")

    placing_mode(view, :insert)
    arm(view, "quarter")
    place(view, 0, 0, "E4")

    assert notes_of(view) == [
             {0, 0, "C3", :whole, 0},
             {0, 0, "E4", :quarter, 0},
             {0, 960, "C4", :quarter, 0}
           ]
  end

  describe "Overlay types over time" do
    test "a half replaces two beats of whatever is there", %{conn: conn} do
      view = draft(conn)
      arm(view, "quarter")
      place(view, 0, 0, "C4")
      place(view, 0, 960, "E4")
      place(view, 0, 1920, "G4")
      arm(view, "half")
      place(view, 0, 0, "A4")

      assert notes_of(view) == [{0, 0, "A4", :half, 0}, {0, 1920, "G4", :quarter, 0}]
    end

    test "a short note on a long one leaves rests for the rest of its time", %{conn: conn} do
      view = draft(conn)
      arm(view, "whole")
      place(view, 0, 0, "C4")
      arm(view, "quarter")
      place(view, 0, 0, "E4")

      assert notes_of(view) == [{0, 0, "E4", :quarter, 0}]
    end

    test "a note sounding into the new one's time is shortened", %{conn: conn} do
      view = draft(conn)
      arm(view, "half")
      place(view, 0, 0, "C4")
      arm(view, "quarter")
      place(view, 0, 960, "E4")

      assert notes_of(view) == [{0, 0, "C4", :quarter, 0}, {0, 960, "E4", :quarter, 0}]
    end

    test "a note running past the bar line is tied over it", %{conn: conn} do
      view = draft(conn)
      arm(view, "half")
      place(view, 0, 2880, "C4")

      assert notes_of(view) == [{0, 2880, "C4", :quarter, 0}, {1, 0, "C4", :quarter, 0}]
    end

    test "placing a note over itself changes nothing", %{conn: conn} do
      view = draft(conn)
      arm(view, "half")
      place(view, 0, 0, "D4")
      place(view, 0, 0, "D4")

      assert notes_of(view) == [{0, 0, "D4", :half, 0}]
    end
  end

  describe "Insert mode leaves no gaps" do
    setup %{conn: conn} do
      %{view: draft(conn, :insert)}
    end

    defp user_rests(view) do
      for {m, i} <- Enum.with_index(session_of(view).score.measures),
          r <- m.rests,
          not r.filler,
          do: {i, r.offset, r.value}
    end

    test "entering notes one after another, wherever the clicks land", %{view: view} do
      # A half clicked on beat 2 of an empty bar goes on beat 1.
      arm(view, "half")
      place(view, 0, 960, "D4")
      assert notes_of(view) == [{0, 0, "D4", :half, 0}]

      # A quarter in front of it pushes it right; the bar's closing rest shrinks.
      arm(view, "quarter")
      place(view, 0, 0, "C4")
      assert notes_of(view) == [{0, 0, "C4", :quarter, 0}, {0, 960, "D4", :half, 0}]

      assert [%{offset: 2880, value: :quarter}] =
               for(r <- hd(session_of(view).score.measures).rests, r.staff == :treble, do: r)

      # In front of the rests after the music, as in front of any item: the
      # bar's closing rest, and bar 3's whole rest, the bars between kept.
      place(view, 0, 2880, "E4")
      place(view, 2, 0, "G4")
      view |> element("#palette-rest-toggle") |> render_click()
      arm(view, "quarter")
      place(view, 2, 960, "B4")
      view |> element("#palette-rest-toggle") |> render_click()
      arm(view, "quarter")
      place(view, 2, 1920, "F4")

      assert notes_of(view) == [
               {0, 0, "C4", :quarter, 0},
               {0, 960, "D4", :half, 0},
               {0, 2880, "E4", :quarter, 0},
               {2, 0, "G4", :quarter, 0},
               {2, 1920, "F4", :quarter, 0}
             ]

      assert user_rests(view) == [{2, 960, :quarter}]
    end

    test "in front of a note or a rest mid-bar, moving it and what follows", %{view: view} do
      arm(view, "half")
      place(view, 0, 0, "C4")
      arm(view, "quarter")
      place(view, 0, 1920, "E4")
      # C4 (half), E4 (quarter), then the bar's closing quarter rest.

      place(view, 0, 1920, "D4")

      assert notes_of(view) == [
               {0, 0, "C4", :half, 0},
               {0, 1920, "D4", :quarter, 0},
               {0, 2880, "E4", :quarter, 0}
             ]

      # In front of the rest that now follows E4 in bar 1: it moves right too.
      place(view, 1, 0, "B4")
      assert {1, 0, "B4", :quarter, 0} in notes_of(view)
    end

    test "the space after a bar's last item is the next bar's: what is left of it stays",
         %{view: view} do
      arm(view, "quarter")
      for {offset, spn} <- [{0, "C4"}, {960, "D4"}, {1920, "E4"}], do: place(view, 0, offset, spn)
      place(view, 1, 0, "G4")
      # Bar 1: C4 D4 E4 and its closing quarter rest; bar 2 starts with G4.

      # Right of the rest the browser sends the next bar's start.
      place(view, 1, 0, "B4")

      assert [_c, _d, _e, {1, 0, "B4", :quarter, 0}, {1, 960, "G4", :quarter, 0}] =
               notes_of(view)

      assert [%{offset: 2880, value: :quarter}] =
               for(r <- hd(session_of(view).score.measures).rests, r.staff == :treble, do: r)
    end

    test "after the last bar's music, a bar is added for the new note", %{view: view} do
      arm(view, "quarter")
      place(view, 4, 0, "C4")
      assert length(session_of(view).score.measures) == 5
      assert notes_of(view) == [{4, 0, "C4", :quarter, 0}]

      placing_mode(view, :overlay)
      place(view, 5, 0, "D4")
      assert length(session_of(view).score.measures) == 6
      assert {5, 0, "D4", :quarter, 0} in notes_of(view)
    end

    test "a note longer than what is left of the bar is tied over it", %{view: view} do
      arm(view, "half")
      place(view, 0, 0, "C4")
      arm(view, "quarter")
      place(view, 0, 1920, "D4")
      arm(view, "half")
      place(view, 0, 2880, "E4")

      assert notes_of(view) == [
               {0, 0, "C4", :half, 0},
               {0, 1920, "D4", :quarter, 0},
               {0, 2880, "E4", :quarter, 0},
               {1, 0, "E4", :quarter, 0}
             ]
    end
  end

  test "a chord quality builds on the clicked note", %{conn: conn} do
    view = draft(conn)
    view |> element("#palette-chord-major") |> render_click()
    place(view, 0, 0, "C4")

    assert Enum.map(notes_of(view), &elem(&1, 2)) == ["C4", "E4", "G4"]
  end

  test "a scale degree builds the key's chord in the clicked octave", %{conn: conn, scope: scope} do
    version = version_fixture(scope, key: %{sf: 1})

    {:ok, view, _html} =
      live(conn, LibraryComponents.version_path(version.key.composition.id, version.key, 1))

    view |> element("#palette-degree-5") |> render_click()
    place(view, 0, 0, "C4")

    assert Enum.map(notes_of(view), &elem(&1, 2)) == ["D4", "F♯4", "A4"]
  end

  describe "chord mode" do
    test "length then chord, or chord then length, places the same chord", %{conn: conn} do
      view = draft(conn)
      arm(view, "half")
      view |> element("#palette-chord-minor") |> render_click()
      place(view, 0, 0, "A3")

      other = draft(conn)
      other |> element("#palette-chord-minor") |> render_click()
      arm(other, "half")
      place(other, 0, 0, "A3")

      expected = [{0, 0, "A3", :half, 0}, {0, 0, "C4", :half, 0}, {0, 0, "E4", :half, 0}]
      assert notes_of(view) == expected
      assert notes_of(other) == expected
    end

    test "the Chords button names the chord; picking it again or Single notes goes back to notes",
         %{conn: conn} do
      view = draft(conn)
      view |> element("#palette-chord-minor") |> render_click()
      assert has_element?(view, "#palette-chords[aria-pressed=true]", "Chord: min")
      assert has_element?(view, "#palette-quarter[aria-pressed=true]")

      view |> element("#palette-chord-minor") |> render_click()
      refute has_element?(view, "#palette-chords[aria-pressed=true]")
      assert has_element?(view, "#palette-quarter[aria-pressed=true]")

      view |> element("#palette-degree-2") |> render_click()
      view |> element("#palette-single-notes") |> render_click()
      place(view, 0, 0, "C4")
      assert notes_of(view) == [{0, 0, "C4", :quarter, 0}]
    end

    test "chords are off for rests", %{conn: conn} do
      view = draft(conn)
      view |> element("#palette-chord-major") |> render_click()
      view |> element("#palette-rest-toggle") |> render_click()

      assert has_element?(view, "#palette-chords[aria-disabled=true]")
      refute has_element?(view, "#palette-chords[aria-pressed=true]")
      view |> element("#palette") |> render_hook("arm_chord", %{"quality" => "major"})
      refute has_element?(view, "#palette-chords[aria-pressed=true]")
    end

    test "with nothing picked, a chord turns the selected notes into chords on them",
         %{conn: conn} do
      view = draft(conn)
      arm(view, "quarter")
      place(view, 0, 0, "C4")
      place(view, 0, 960, "D4")
      canvas_hook(view, "disarm", %{})

      canvas_hook(view, "select_range", %{"from" => 0, "to" => 1920})
      view |> element("#palette-chord-major") |> render_click()

      assert notes_of(view) == [
               {0, 0, "C4", :quarter, 0},
               {0, 0, "E4", :quarter, 0},
               {0, 0, "G4", :quarter, 0},
               {0, 960, "D4", :quarter, 0},
               {0, 960, "F♯4", :quarter, 0},
               {0, 960, "A4", :quarter, 0}
             ]

      assert MapSet.size(session_of(view).selection) == 6
      refute has_element?(view, "#palette-chords[aria-pressed=true]")
    end
  end

  test "an armed rest places a rest", %{conn: conn} do
    view = draft(conn)
    view |> element("#palette-rest-toggle") |> render_click()
    arm(view, "quarter")
    place(view, 0, 0, "B4")

    rests = for m <- session_of(view).score.measures, r <- m.rests, not r.filler, do: r
    assert [%{offset: 0, value: :quarter}] = rests
    assert notes_of(view) == []
  end

  test "the hook element carries the geometry and the armed item", %{conn: conn} do
    view = draft(conn)
    assert has_element?(view, "#score-editor[data-geometry]")
    arm(view, "eighth")
    assert has_element?(view, "#score-editor[data-armed*='eighth']")
  end
end
