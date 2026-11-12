defmodule DrawMusicWeb.Editor.TempoDialogTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DrawMusic.Music.{Context, Score, TempoChange}
  alias DrawMusicWeb.ComponentHostLive
  alias DrawMusicWeb.Editor.TempoDialog
  alias DrawMusicWeb.{TempoForm, TempoTarget}

  setup :register_and_log_in_user

  @ctx %Context{}

  # A change at beat 2 of bar 1 that may reach the next change, 3 beats on.
  defp target(id \\ nil, params \\ TempoForm.params(100, @ctx)) do
    %TempoTarget{
      id: id,
      tick: 960,
      params: params,
      reach: 3840,
      until: :next_change,
      max_beats: "3"
    }
  end

  defp host(conn, attrs) do
    session = %{"component" => TempoDialog, "attrs" => attrs, "test_pid" => self()}
    {:ok, view, _html} = live_isolated(conn, ComponentHostLive, session: session)
    view
  end

  # Runs a reported edit on a score with room for it.
  defp run({:edit, fun, :select}), do: fun.(Score.new(2), @ctx)
  defp run({:edit, fun}), do: fun.(%{Score.new(2) | tempos: [mark()]}, @ctx)

  defp mark, do: %TempoChange{id: "t", tick: 960, bpm: 60}

  test "Save reports the change, to be selected, then close", %{conn: conn} do
    view = host(conn, %{target: target(), ctx: @ctx})
    view |> form("#tempo-form", tempo: %{bpm: "60"}) |> render_submit()

    assert_received {:component_sent, {:editor, {:edit, _fun, :select} = edit}}
    assert_received {:component_sent, {:editor, :close}}
    assert {:ok, %Score{tempos: [%{tick: 960, bpm: 60, id: id}]}, [id]} = run(edit)
  end

  test "a gradual change shows what it does and how far it may go", %{conn: conn} do
    view = host(conn, %{target: target(), ctx: @ctx})
    view |> form("#tempo-form", tempo: %{gradual: "true"}) |> render_change()
    view |> form("#tempo-form", tempo: %{bpm: "80", to_bpm: "100"}) |> render_change()

    assert has_element?(view, "#tempo-ramp", "accel.")
    assert has_element?(view, "#tempo-room", "At most 3 beats, up to the next tempo change")

    view |> form("#tempo-form", tempo: %{beats: "4"}) |> render_submit()
    assert has_element?(view, "#tempo-form", "can be at most 3")
    refute_received {:component_sent, _message}
  end

  test "Delete is only for an existing change, and reports its removal", %{conn: conn} do
    view = host(conn, %{target: target(), ctx: @ctx})
    refute has_element?(view, "#tempo-delete")

    view = host(conn, %{target: target("t", TempoForm.params(mark(), @ctx)), ctx: @ctx})
    view |> element("#tempo-delete") |> render_click()

    assert_received {:component_sent, {:editor, {:edit, _fun} = edit}}
    assert_received {:component_sent, {:editor, :close}}
    assert {:ok, %Score{tempos: []}} = run(edit)
  end

  test "Cancel reports close", %{conn: conn} do
    view = host(conn, %{target: target(), ctx: @ctx})
    view |> element("#tempo-form button", "Cancel") |> render_click()

    assert_received {:component_sent, {:editor, :close}}
  end

  test "needs its inputs", %{conn: conn} do
    assert_raise ArgumentError, ~r/TempoDialog needs/, fn -> host(conn, %{ctx: @ctx}) end
  end
end
