defmodule DrawMusicWeb.EditorCommandsTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Music.{Context, Note, Rest, Score}
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

  defp event(%Score{measures: [bar | _]}, id) do
    Enum.find(bar.notes ++ bar.rests, &(&1.id == id))
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
end
