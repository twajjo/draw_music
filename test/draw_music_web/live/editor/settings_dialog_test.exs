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
    "tempo_marking" => "Moderato",
    "tempo_text" => "Moderato",
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

  # A marking is chosen first: its words are then the ones that can be printed.
  defp apply_settings(view, changes) do
    settings = Map.merge(@settings, changes)
    choose_marking(view, settings["tempo_marking"])
    view |> form("#settings-form", settings: settings) |> render_submit()
  end

  defp choose_marking(view, marking) do
    view |> form("#settings-form", settings: %{"tempo_marking" => marking}) |> render_change()
  end

  defp print(view, word) do
    view |> form("#settings-form", settings: %{"tempo_text" => word}) |> render_change()
  end

  defp printed?(view, word),
    do: has_element?(view, "#settings-tempo-text option[selected][value='#{word}']")

  test "starts from the score's settings", %{view: view} do
    assert has_element?(view, "#settings-tempo-text option[selected][value='Andante']")

    assert has_element?(view, "#settings-form input[name='settings[time_num]'][value='4']")
  end

  test "reports settings that pass, with their key and marking", %{view: view} do
    apply_settings(view, %{
      "key" => "g-major",
      "time_num" => "3",
      "tempo_marking" => "Adagio",
      "tempo_text" => "Adagio"
    })

    assert_received {:component_sent,
                     {:editor, {:settings, {1, :major}, %{time_num: 3, tempo_text: "Adagio"}}}}
  end

  test "there is always a marking: a blank one becomes Moderato", %{view: view} do
    refute has_element?(view, "#settings-tempo-text option[value='']")

    view
    |> element("#settings-form")
    |> render_submit(%{"settings" => Map.put(@settings, "tempo_text", "")})

    assert_received {:component_sent, {:editor, {:settings, _key, %{tempo_text: "Moderato"}}}}
  end

  test "a refused setting stays in the form and reports nothing", %{view: view} do
    apply_settings(view, %{"pickup_beats" => "4"})

    assert has_element?(view, "#settings-form", "must be shorter than a full measure")
    refute_received {:component_sent, _message}
  end

  describe "the tempo marking" do
    test "each marking shows its words in every language that has one", %{view: view} do
      assert has_element?(
               view,
               "#settings-tempo-marking option[value='Allegro']",
               "Allegro · Schnell · Vite · Fast"
             )

      assert has_element?(view, "#settings-tempo-marking optgroup[label='By character']")
    end

    test "only the marking's own words can be printed", %{view: view} do
      choose_marking(view, "Allegro con brio")

      assert printed?(view, "Allegro con brio")
      assert has_element?(view, "#settings-tempo-text option[value='Fast, with vigour']")
      refute has_element?(view, "#settings-tempo-text option[value='Andante']")
    end

    test "another marking is printed in the same language, where it has a word", %{view: view} do
      choose_marking(view, "Allegro")
      print(view, "Schnell")
      choose_marking(view, "Lento")
      assert printed?(view, "Langsam")

      choose_marking(view, "Tempo di valse")
      assert printed?(view, "Tempo di valse")

      view |> form("#settings-form") |> render_submit()

      assert_received {:component_sent,
                       {:editor, {:settings, _key, %{tempo_text: "Tempo di valse"}}}}
    end

    test "an unknown word is refused", %{view: view} do
      view
      |> element("#settings-form")
      |> render_submit(%{
        "settings" => Map.merge(@settings, %{"tempo_marking" => "", "tempo_text" => "Zippy"})
      })

      assert has_element?(view, "#settings-form", "isn't a known tempo marking")
      refute_received {:component_sent, _message}
    end
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
