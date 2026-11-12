defmodule DrawMusicWeb.Editor.NoteMenuTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DrawMusic.Music.{Context, Note, Score, Session}
  alias DrawMusicWeb.{ComponentHostLive, ContextMenu, TempoTarget}
  alias DrawMusicWeb.Editor.NoteMenu

  setup :register_and_log_in_user

  @ctx %Context{}

  # C4 on beat 1 and E4 on beat 2 of the first bar.
  setup do
    c4 = %Note{id: Ecto.UUID.generate(), staff: :treble, offset: 0, value: :quarter, step: 28}
    e4 = %Note{id: Ecto.UUID.generate(), staff: :treble, offset: 960, value: :quarter, step: 30}
    [measure | rest] = Score.new(2).measures
    score = %Score{measures: [%{measure | notes: [c4, e4]} | rest]}
    %{score: score, c4: c4, e4: e4}
  end

  defp host(conn, score, menu) do
    attrs = %{menu: menu, score: score, ctx: @ctx}
    session = %{"component" => NoteMenu, "attrs" => attrs, "test_pid" => self()}
    {:ok, view, _html} = live_isolated(conn, ComponentHostLive, session: session)
    view
  end

  defp menu_for(%Note{id: id}), do: %ContextMenu{id: id, ids: [id], kind: :note, x: 10, y: 10}

  defp selection_menu(ids) do
    %ContextMenu{id: hd(ids), ids: ids, kind: :selection, x: 10, y: 10}
  end

  defp note_ids(%Score{measures: measures}) do
    Enum.flat_map(measures, fn measure -> Enum.map(measure.notes, & &1.id) end)
  end

  test "an action reports its edit, then closes", %{conn: conn, score: score, e4: e4} do
    view = host(conn, score, menu_for(e4))
    view |> element("#menu-split") |> render_click()

    assert_received {:component_sent, {:editor, {:edit, fun}}}
    assert_received {:component_sent, {:editor, :close}}
    assert {:ok, %Score{} = split, _halves} = fun.(score, @ctx)
    assert length(note_ids(split)) == 3
  end

  test "Copy selects the menu's notes and copies them", %{conn: conn, score: score} = notes do
    ids = [notes.c4.id, notes.e4.id]
    view = host(conn, score, selection_menu(ids))
    view |> element("#menu-copy") |> render_click()

    assert_received {:component_sent, {:editor, {:session, fun}}}
    assert_received {:component_sent, {:editor, :close}}
    refute_received {:component_sent, {:editor, {:edit, _fun}}}

    copied = fun.(Session.new(score, @ctx))
    assert copied.selection == MapSet.new(ids)
    assert copied.clipboard
  end

  test "Cut copies, then deletes", %{conn: conn, score: score, c4: c4} = notes do
    view = host(conn, score, selection_menu([c4.id]))
    view |> element("#menu-cut") |> render_click()

    assert_received {:component_sent, {:editor, {:session, _copy}}}
    assert_received {:component_sent, {:editor, {:edit, delete}}}
    assert_received {:component_sent, {:editor, :close}}
    assert {:ok, cut} = delete.(score, @ctx)
    assert note_ids(cut) == [notes.e4.id]
  end

  test "a selection gets transpose and reverse, not a note's actions",
       %{conn: conn, score: score, c4: c4, e4: e4} do
    view = host(conn, score, selection_menu([c4.id, e4.id]))

    assert has_element?(view, "#menu-reverse")
    assert has_element?(view, "#menu-transpose-octave-up")
    refute has_element?(view, "#menu-split")
  end

  test "Tempo change here… opens the tempo dialog where the note starts",
       %{conn: conn, score: score, e4: e4} do
    view = host(conn, score, menu_for(e4))
    view |> element("#menu-tempo") |> render_click()

    assert_received {:component_sent, {:editor, {:open, {:tempo, %TempoTarget{} = target}}}}
    assert target.tick == 960
    assert target.id == nil
    refute_received {:component_sent, {:editor, :close}}
  end

  test "Esc or a click outside closes it", %{conn: conn, score: score, c4: c4} do
    view = host(conn, score, menu_for(c4))
    view |> element("#context-menu") |> render_keydown(%{"key" => "Escape"})

    assert_received {:component_sent, {:editor, :close}}
  end

  describe "TempoTarget.at_event/3" do
    test "none on the opening beat, whose tempo is the settings'", %{score: score, c4: c4} do
      assert TempoTarget.at_event(score, @ctx, c4.id) == {:error, :opening_beat}
    end

    test "none for a note that isn't there", %{score: score} do
      assert TempoTarget.at_event(score, @ctx, Ecto.UUID.generate()) == {:error, :not_found}
    end
  end
end
