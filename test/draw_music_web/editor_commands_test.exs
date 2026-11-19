defmodule DrawMusicWeb.EditorCommandsTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Music.{Context, Editing, Note, Rest, Score}
  alias DrawMusicWeb.EditorCommands

  @ctx %Context{}

  # A C4 quarter on beat 1, an E4 quarter on beat 3, an eighth rest on
  # beat 4: each has room for a dot.
  setup do
    c4 = %Note{id: Ecto.UUID.generate(), staff: :treble, offset: 0, value: :quarter, step: 28}
    e4 = %Note{id: Ecto.UUID.generate(), staff: :treble, offset: 1920, value: :quarter, step: 30}
    rest = %Rest{id: Ecto.UUID.generate(), staff: :treble, offset: 2880, value: :eighth}
    [measure | others] = Score.new(2).measures
    bar = %{measure | notes: [c4, e4], rests: [rest]}
    %{score: %Score{measures: [bar | others]}, c4: c4, e4: e4, rest: rest}
  end

  describe "toggle_dots/1" do
    test "dots notes and rests that aren't all dotted", %{score: score, c4: c4, rest: rest} do
      edit = EditorCommands.toggle_dots([c4.id, rest.id, "tempo-mark-id"])
      assert {:ok, dotted} = edit.(score, @ctx)
      assert event(dotted, c4.id).dots == 1
      assert event(dotted, rest.id).dots == 1
    end

    test "takes the dots off when every one has one", %{score: score, c4: c4} do
      {:ok, dotted} = EditorCommands.toggle_dots([c4.id]).(score, @ctx)
      assert {:ok, undotted} = EditorCommands.toggle_dots([c4.id]).(dotted, @ctx)
      assert event(undotted, c4.id).dots == 0
    end
  end

  describe "set_alter/2" do
    test "changes the notes and leaves rests alone", %{score: score, c4: c4, e4: e4, rest: rest} do
      edit = EditorCommands.set_alter([c4.id, rest.id], 1)
      assert {:ok, sharpened} = edit.(score, @ctx)

      assert event(sharpened, c4.id).alter == 1
      assert event(sharpened, e4.id).alter == e4.alter
      assert event(sharpened, rest.id)
    end
  end

  describe "paste/4" do
    setup %{score: score, c4: c4} do
      %{clipboard: Editing.copy(score, @ctx, [c4.id])}
    end

    test "Insert goes ahead of the selection, which moves right",
         %{score: score, clipboard: clipboard, e4: e4} do
      edit = EditorCommands.paste(clipboard, 1920, true, [e4.id])
      assert {:ok, pasted, _ids} = edit.(score, @ctx)
      assert notes(pasted) == [{0, 28}, {1920, 28}, {2880, 30}]
    end

    test "Overlay replaces the selection; nothing moves",
         %{score: score, clipboard: clipboard, e4: e4} do
      edit = EditorCommands.paste(clipboard, 1920, false, [e4.id])
      assert {:ok, pasted, _ids} = edit.(score, @ctx)
      assert notes(pasted) == [{0, 28}, {1920, 28}]
    end

    test "Overlay with nothing selected overwrites the clipboard's length from the tick",
         %{score: score, clipboard: clipboard} do
      edit = EditorCommands.paste(clipboard, 1440, false, [])
      assert {:ok, pasted, _ids} = edit.(score, @ctx)
      # E4 starts inside the pasted quarter (1440 to 2400), so it goes.
      assert notes(pasted) == [{0, 28}, {1440, 28}]
    end
  end

  defp event(%Score{measures: [bar | _]}, id) do
    Enum.find(bar.notes ++ bar.rests, &(&1.id == id))
  end

  # {offset, step} of the first bar's notes, in time order.
  defp notes(%Score{measures: [bar | _]}) do
    bar.notes
    |> Enum.map(&{&1.offset, &1.step})
    |> Enum.sort()
  end
end
