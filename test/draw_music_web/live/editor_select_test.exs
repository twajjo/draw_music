defmodule DrawMusicWeb.EditorSelectTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusicWeb.EditorHelpers

  alias DrawMusic.MusicHelpers

  setup :register_and_log_in_user

  # A draft with C4 and E4 quarters at the start of bar 0.
  setup %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "arm", %{"kind" => "note", "value" => "quarter"})
    place(view, 0, 0, "C4")
    place(view, 0, 960, "E4")
    render_hook(view, "disarm", %{})
    %{view: view}
  end

  defp id_at(view, offset) do
    session_of(view).score.measures
    |> hd()
    |> Map.fetch!(:notes)
    |> Enum.find(&(&1.offset == offset))
    |> Map.fetch!(:id)
  end

  defp select(view, ids, add \\ false),
    do: render_hook(view, "select", %{"ids" => ids, "add" => add})

  test "a time range selects everything in it, rests included", %{view: view} do
    render_hook(view, "select_range", %{"from" => 0, "to" => 3840})
    assert count(view, "#score [id^='note-'].selected") == 2
    # The treble's half rest after the notes, and the bass's whole-bar rest.
    assert count(view, "#score [id^='rest-'].selected") == 2
  end

  describe "select all" do
    defp all_selected?(view) do
      has_element?(view, "#score [id^='note-'].selected") and
        not has_element?(view, "#score [id^='note-']:not(.selected)") and
        not has_element?(view, "#score [id^='rest-']:not(.selected)")
    end

    test "Ctrl+A selects every note and rest, on both staves", %{view: view} do
      render_hook(view, "select_all", %{})
      assert all_selected?(view)
      assert count(view, "#score [id^='note-'].selected") == 2
    end

    test "the palette button does the same", %{view: view} do
      view |> element("#palette-select-all") |> render_click()
      assert all_selected?(view)
    end

    test "deleting after it leaves no notes", %{view: view} do
      render_hook(view, "select_all", %{})
      render_hook(view, "delete", %{})
      assert notes_of(view) == []
    end

    test "Play mode ignores it", %{view: view} do
      view |> element("#palette-mode-play") |> render_click()
      render_hook(view, "select_all", %{})
      refute has_element?(view, "#score .selected")
    end
  end

  test "a range takes in a filler rest only if the rest ends inside it", %{view: view} do
    render_hook(view, "select_range", %{"from" => 0, "to" => 1920})
    assert count(view, "#score [id^='note-'].selected") == 2
    refute has_element?(view, "#score [id^='rest-'].selected")
  end

  test "shift-click toggles one note in and out", %{view: view} do
    id = id_at(view, 0)
    select(view, [id], true)
    assert has_element?(view, "#note-#{id}.selected")
    select(view, [id], true)
    refute has_element?(view, "#note-#{id}.selected")
  end

  test "arrows move the selection by scale steps and beats", %{view: view} do
    select(view, [id_at(view, 960)])

    render_hook(view, "move", %{"dir" => "up"})
    render_hook(view, "move", %{"dir" => "right"})

    assert {0, 1920, "F4", :quarter, 0} in notes_of(view)
  end

  test "in Overlay, delete removes the selection and leaves the rest where it was",
       %{view: view} do
    placing_mode(view, :overlay)
    select(view, [id_at(view, 0)])
    render_hook(view, "delete", %{})
    assert notes_of(view) == [{0, 960, "E4", :quarter, 0}]
  end

  test "in Insert, delete removes the selection and closes the gap", %{view: view} do
    select(view, [id_at(view, 0)])
    render_hook(view, "delete", %{})
    assert notes_of(view) == [{0, 0, "E4", :quarter, 0}]
  end

  test "Shift moves by octaves, Ctrl by semitones", %{view: view} do
    select(view, [id_at(view, 0)])
    render_hook(view, "move", %{"dir" => "up", "by" => "octave"})
    assert {0, 0, "C5", :quarter, 0} in notes_of(view)

    render_hook(view, "move", %{"dir" => "down", "by" => "semitone"})
    assert {0, 0, "B4", :quarter, 0} in notes_of(view)
  end

  test "an octave move keeps a note's accidental", %{view: view} do
    render_hook(view, "arm", %{"kind" => "note", "value" => "quarter"})
    place(view, 0, 1920, "F#4", alter: true)
    render_hook(view, "disarm", %{})
    select(view, [id_at(view, 1920)])

    render_hook(view, "move", %{"dir" => "up", "by" => "octave"})
    assert {0, 1920, "F♯5", :quarter, 0} in notes_of(view)
  end

  test "a paste far past the end lands at the end", %{view: view} do
    select(view, [id_at(view, 0)])
    render_hook(view, "copy", %{})
    render_hook(view, "paste", %{"at" => 1_000_000_000})

    assert length(session_of(view).score.measures) == 5
    assert {4, 0, "C4", :quarter, 0} in notes_of(view)
  end

  describe "selection menu" do
    setup %{view: view} do
      render_hook(view, "select_range", %{"from" => 0, "to" => 3840})
      id = id_at(view, 0)

      render_hook(view, "open_menu", %{
        "id" => id,
        "x" => 10,
        "y" => 10,
        "step" => 30,
        "staff" => "treble"
      })

      :ok
    end

    test "offers selection actions", %{view: view} do
      assert has_element?(view, "#menu-reverse")
      refute has_element?(view, "#menu-split")
    end

    test "transposes the selection", %{view: view} do
      view |> element("#menu-transpose-octave-up") |> render_click()
      assert notes_of(view) == [{0, 0, "C5", :quarter, 0}, {0, 960, "E5", :quarter, 0}]
    end

    test "transposes by an interval", %{view: view} do
      view |> element("#menu-interval-maj3-up") |> render_click()
      assert notes_of(view) == [{0, 0, "E4", :quarter, 0}, {0, 960, "G♯4", :quarter, 0}]
    end

    # The whole bar is selected, so its closing half rest comes first.
    test "reverses the selection", %{view: view} do
      view |> element("#menu-reverse") |> render_click()
      assert notes_of(view) == [{0, 1920, "E4", :quarter, 0}, {0, 2880, "C4", :quarter, 0}]
    end

    test "deletes the selection", %{view: view} do
      view |> element("#menu-delete") |> render_click()
      assert notes_of(view) == []
    end
  end

  test "copy and paste duplicate at the given tick", %{view: view} do
    render_hook(view, "select_range", %{"from" => 0, "to" => 3840})
    render_hook(view, "copy", %{})
    render_hook(view, "paste", %{"at" => 3840})

    assert {1, 0, "C4", :quarter, 0} in notes_of(view)
    assert {1, 960, "E4", :quarter, 0} in notes_of(view)
  end

  test "cut removes and keeps a copy", %{view: view} do
    placing_mode(view, :overlay)
    select(view, [id_at(view, 0)])
    render_hook(view, "cut", %{})
    render_hook(view, "paste", %{"at" => 1920})

    assert notes_of(view) == [{0, 960, "E4", :quarter, 0}, {0, 1920, "C4", :quarter, 0}]
  end

  test "paste always inserts, moving later music on that staff right", %{view: view} do
    select(view, [id_at(view, 0)])
    render_hook(view, "copy", %{})
    render_hook(view, "paste", %{"at" => 0})

    assert notes_of(view) == [
             {0, 0, "C4", :quarter, 0},
             {0, 960, "C4", :quarter, 0},
             {0, 1920, "E4", :quarter, 0}
           ]
  end

  test "undo and redo step through edits", %{view: view} do
    view |> element("#palette-undo") |> render_click()
    assert notes_of(view) == [{0, 0, "C4", :quarter, 0}]

    view |> element("#palette-redo") |> render_click()
    assert length(notes_of(view)) == 2
  end

  test "moving a selection that undo removed does nothing", %{view: view} do
    id = id_at(view, 960)
    select(view, [id])
    view |> element("#palette-undo") |> render_click()

    render_hook(view, "move", %{"dir" => "up"})
    assert notes_of(view) == [{0, 0, "C4", :quarter, 0}]
    assert count(view, "#score .selected") == 0
  end

  test "a move outside the piano's range is refused", %{view: view} do
    render_hook(view, "arm", %{"kind" => "note", "value" => "quarter"})
    place(view, 0, 1920, "C8")
    render_hook(view, "disarm", %{})
    select(view, [id_at(view, 1920)])

    render_hook(view, "move", %{"dir" => "up"})

    assert has_element?(view, "#flash-error", "That would go outside the piano's range")
    assert {0, 1920, "C8", :quarter, 0} in notes_of(view)
  end

  test "the dot button dots the selection when nothing is armed", %{view: view} do
    select(view, [id_at(view, 960)])
    view |> element("#palette-dot") |> render_click()
    assert {0, 960, "E4", :quarter, 1} in notes_of(view)
  end

  test "number keys arm values in the current row", %{view: view} do
    render_hook(view, "arm_value", %{"value" => "eighth"})
    assert has_element?(view, "#palette-eighth[aria-pressed=true][data-kind=note]")
  end

  test "selection ignores unknown ids", %{view: view} do
    select(view, [Ecto.UUID.generate(), "not-an-id"])
    assert count(view, "#score .selected") == 0
    assert MusicHelpers.notes(session_of(view).score) |> length() == 2
  end
end
