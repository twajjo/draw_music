defmodule DrawMusicWeb.EditorToolsTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DrawMusicWeb.EditorHelpers

  alias DrawMusic.MusicHelpers

  setup :register_and_log_in_user

  setup %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    %{view: view}
  end

  defp put_notes(view, notes) do
    render_hook(view, "lock", %{"kind" => "note", "value" => "quarter"})
    for {offset, spn} <- notes, do: place(view, 0, offset, spn)
    render_hook(view, "disarm", %{})
  end

  defp id_at(view, offset) do
    session_of(view).score.measures
    |> hd()
    |> then(&(&1.notes ++ &1.rests))
    |> Enum.find(&(&1.offset == offset))
    |> Map.fetch!(:id)
  end

  defp open_menu(view, offset, spn \\ "B4") do
    {step, _alter} = MusicHelpers.pitch!(spn)
    id = id_at(view, offset)

    render_hook(view, "open_menu", %{
      "id" => id,
      "x" => 100,
      "y" => 100,
      "step" => step,
      "staff" => "treble"
    })

    id
  end

  describe "dragging" do
    test "dropping moves the dragged notes by scale steps and selects them", %{view: view} do
      put_notes(view, [{0, "C4"}])
      id = id_at(view, 0)
      render_hook(view, "drop", %{"ids" => [id], "steps" => 2})
      assert notes_of(view) == [{0, 0, "E4", :quarter, 0}]
      assert session_of(view).selection == MapSet.new([id])
    end

    test "a note dropped on the other staff moves there and stays selected", %{view: view} do
      put_notes(view, [{960, "C4"}])
      {step, _alter} = MusicHelpers.pitch!("G3")

      render_hook(view, "drop", %{"ids" => [id_at(view, 960)], "staff" => "bass", "step" => step})

      [note] = hd(session_of(view).score.measures).notes
      assert {note.staff, note.offset} == {:bass, 960}
      assert notes_of(view) == [{0, 960, "G3", :quarter, 0}]
      assert session_of(view).selection == MapSet.new([note.id])
    end

    test "a drop naming an unknown staff changes nothing", %{view: view} do
      put_notes(view, [{0, "C4"}])
      render_hook(view, "drop", %{"ids" => [id_at(view, 0)], "staff" => "alto", "step" => 20})
      assert notes_of(view) == [{0, 0, "C4", :quarter, 0}]
    end

    test "a modifier held while dropping sets the accidental", %{view: view} do
      put_notes(view, [{0, "C4"}])
      render_hook(view, "drop", %{"ids" => [id_at(view, 0)], "steps" => 2, "alter" => 1})
      assert notes_of(view) == [{0, 0, "E♯4", :quarter, 0}]
    end
  end

  describe "ties" do
    test "the tie tool ties touching notes of the same pitch", %{view: view} do
      put_notes(view, [{0, "C4"}, {960, "C4"}])
      view |> element("#palette-tie") |> render_click()
      a = id_at(view, 0)
      b = id_at(view, 960)
      render_hook(view, "tie", %{"from" => b, "to" => a})

      assert MusicHelpers.tie_chain(session_of(view).score, a) == [a, b]
      refute has_element?(view, "#palette-tie[aria-pressed=true]")
    end

    test "other pairs are refused with an explanation", %{view: view} do
      put_notes(view, [{0, "C4"}, {960, "D4"}])
      render_hook(view, "tie", %{"from" => id_at(view, 0), "to" => id_at(view, 960)})

      assert has_element?(
               view,
               "#flash-error",
               "Only touching notes of the same pitch can be tied"
             )
    end
  end

  describe "context menu" do
    test "opens at the pointer and closes", %{view: view} do
      put_notes(view, [{0, "C4"}])
      open_menu(view, 0)
      assert has_element?(view, "#context-menu")
      render_hook(view, "close_menu", %{})
      refute has_element?(view, "#context-menu")
    end

    # The browser sends a button's own `value`, not phx-value-value.
    test "length buttons carry their value for the browser", %{view: view} do
      put_notes(view, [{0, "C4"}])
      open_menu(view, 0)
      assert has_element?(view, "#menu-length-half[value=half]")
    end

    test "split", %{view: view} do
      put_notes(view, [{0, "C4"}])
      open_menu(view, 0)
      view |> element("#menu-split") |> render_click()

      assert notes_of(view) == [{0, 0, "C4", :eighth, 0}, {0, 480, "C4", :eighth, 0}]
      refute has_element?(view, "#context-menu")
    end

    test "change length", %{view: view} do
      put_notes(view, [{0, "C4"}])
      open_menu(view, 0)
      view |> element("#menu-length-half") |> render_click()
      assert notes_of(view) == [{0, 0, "C4", :half, 0}]
    end

    test "in Insert mode a longer length moves later music on that staff", %{view: view} do
      put_notes(view, [{0, "C4"}, {960, "E4"}])
      view |> element("#palette-insert") |> render_click()
      open_menu(view, 0)
      view |> element("#menu-length-half") |> render_click()

      assert notes_of(view) == [{0, 0, "C4", :half, 0}, {0, 1920, "E4", :quarter, 0}]
    end

    test "note to rest and back, on the clicked line or space", %{view: view} do
      put_notes(view, [{0, "C4"}])
      open_menu(view, 0)
      view |> element("#menu-to-rest") |> render_click()
      assert notes_of(view) == []

      open_menu(view, 0, "G4")
      view |> element("#menu-to-note") |> render_click()
      assert notes_of(view) == [{0, 0, "G4", :quarter, 0}]
    end

    test "tie to next, untie and delete", %{view: view} do
      put_notes(view, [{0, "C4"}, {960, "C4"}])
      a = open_menu(view, 0)
      view |> element("#menu-tie-next") |> render_click()
      assert length(MusicHelpers.tie_chain(session_of(view).score, a)) == 2

      open_menu(view, 0)
      view |> element("#menu-untie") |> render_click()
      assert MusicHelpers.tie_chain(session_of(view).score, a) == [a]

      open_menu(view, 0)
      view |> element("#menu-delete") |> render_click()
      assert notes_of(view) == [{0, 0, "C4", :quarter, 0}]
    end

    test "length changes apply to the whole chord", %{view: view} do
      view |> element("#palette-chord-major") |> render_click()
      place(view, 0, 0, "C4")

      open_menu(view, 0)
      view |> element("#menu-length-half") |> render_click()
      assert Enum.map(notes_of(view), &elem(&1, 3)) == [:half, :half, :half]

      open_menu(view, 0)
      view |> element("#menu-split") |> render_click()
      assert length(notes_of(view)) == 6
    end

    test "a menu action with no menu open is ignored", %{view: view} do
      put_notes(view, [{0, "C4"}])
      render_hook(view, "split", %{})
      assert notes_of(view) == [{0, 0, "C4", :quarter, 0}]
    end

    test "only opens for notes and rests in the score", %{view: view} do
      render_hook(view, "open_menu", %{
        "id" => Ecto.UUID.generate(),
        "x" => 1,
        "y" => 1,
        "step" => 30,
        "staff" => "treble"
      })

      refute has_element?(view, "#context-menu")
    end
  end

  describe "measures" do
    test "insert a bar before another", %{view: view} do
      put_notes(view, [{0, "C4"}])
      view |> element("#measure-0-insert") |> render_click()
      assert notes_of(view) == [{1, 0, "C4", :quarter, 0}]
    end

    test "add a bar at the end", %{view: view} do
      view |> element("#add-measure") |> render_click()
      assert length(session_of(view).score.measures) == 5
    end

    test "delete bars, but never the last one", %{view: view} do
      for _ <- 1..3, do: view |> element("#measure-0-delete") |> render_click()
      assert length(session_of(view).score.measures) == 1

      view |> element("#measure-0-delete") |> render_click()
      assert has_element?(view, "#flash-error", "A score needs at least one bar")
    end
  end
end
