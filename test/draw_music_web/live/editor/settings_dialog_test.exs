defmodule DrawMusicWeb.Editor.SettingsDialogTest do
  use DrawMusicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DrawMusic.Music.Context
  alias DrawMusicWeb.ComponentHostLive
  alias DrawMusicWeb.Editor.SettingsDialog

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

  defp host(conn, attrs) do
    session = %{"component" => SettingsDialog, "attrs" => attrs, "test_pid" => self()}
    {:ok, view, _html} = live_isolated(conn, ComponentHostLive, session: session)
    view
  end

  setup %{conn: conn} do
    ctx = %Context{sf: 0, mode: :major, time_num: 4, time_den: 4, tempo_bpm: 100}
    %{view: host(conn, %{ctx: ctx, tempo_text: "Andante", instrument: 0})}
  end

  defp apply_settings(view, changes) do
    view |> form("#settings-form", settings: Map.merge(@settings, changes)) |> render_submit()
  end

  test "starts from the score's settings", %{view: view} do
    assert has_element?(
             view,
             "#settings-form input[name='settings[tempo_text]'][value='Andante']"
           )

    assert has_element?(view, "#settings-form input[name='settings[time_num]'][value='4']")
  end

  test "reports settings that pass, with their key and marking", %{view: view} do
    apply_settings(view, %{"key" => "g-major", "time_num" => "3", "tempo_text" => "Adagio"})

    assert_received {:component_sent,
                     {:editor, {:settings, {1, :major}, %{time_num: 3, tempo_text: "Adagio"}}}}
  end

  test "a blank marking is reported as none", %{view: view} do
    apply_settings(view, %{})

    assert_received {:component_sent, {:editor, {:settings, {0, :major}, %{tempo_text: nil}}}}
  end

  test "a refused setting stays in the form and reports nothing", %{view: view} do
    apply_settings(view, %{"pickup_beats" => "4"})

    assert has_element?(view, "#settings-form", "must be shorter than a full measure")
    refute_received {:component_sent, _message}
  end

  test "Cancel reports close", %{view: view} do
    view |> element("#settings-form button", "Cancel") |> render_click()

    assert_received {:component_sent, {:editor, :close}}
  end

  test "needs its inputs", %{conn: conn} do
    assert_raise ArgumentError, ~r/SettingsDialog needs/, fn ->
      host(conn, %{instrument: 0})
    end
  end
end
