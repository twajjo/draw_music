defmodule DrawMusicWeb.ShortcutsTest do
  use ExUnit.Case, async: true

  alias DrawMusicWeb.Shortcuts

  @hook_keys "assets/js/score_editor/keys.json"

  test "every key the editor handles is on the cheat-sheet, and no others" do
    handled =
      @hook_keys
      |> File.read!()
      |> JSON.decode!()
      |> MapSet.new()

    assert handled == MapSet.new(Shortcuts.handled_keys())
  end

  test "every Phase 4 and 5 mouse gesture has an entry" do
    gestures = for %{mouse: mouse} <- Shortcuts.all(), mouse, do: mouse

    for gesture <- [
          "press, drag, let go",
          "click note",
          "drag note",
          "shift-click",
          "ctrl-click",
          "drag note to note",
          "drag empty area",
          "right-click",
          "double-click palette item",
          "click note (Play mode)",
          "drag (Play mode)"
        ] do
      assert gesture in gestures, "no cheat-sheet entry for #{inspect(gesture)}"
    end
  end

  test "every entry belongs to a known group and mode" do
    for shortcut <- Shortcuts.all() do
      assert shortcut.group in Shortcuts.groups()
      assert shortcut.modes != [] and Enum.all?(shortcut.modes, &(&1 in [:edit, :play]))
    end
  end

  test "Play mode lists Playback and Modes first" do
    assert [%{group: "Playback"} | _] = Shortcuts.for_mode(:play)
    assert [%{group: "Placing"} | _] = Shortcuts.for_mode(:edit)
  end
end
