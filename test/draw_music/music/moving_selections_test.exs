defmodule DrawMusic.Music.MovingSelectionsTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Music.{Context, Editing, Pitch, Score, Timeline}

  @ctx %Context{}

  # The worked example of plans/moving-selections.md, on the treble staff:
  # bar 1 C5, a quarter rest, a half rest; bar 2 a quarter rest, G4, C5, a
  # quarter rest.
  setup do
    score = Editing.fill_rests(Score.new(2), @ctx)
    {score, _c} = treble(score, 0, "C5", :quarter, 0)
    {score, _g} = treble(score, 1, "G4", :quarter, 960)
    {score, _c} = treble(score, 1, "C5", :quarter, 1920)
    %{score: score}
  end

  test "the worked example: the half rest moves whole; what it passes moves back",
       %{score: score} do
    half_rest = rest_at(score, 1920)

    {:ok, score, [^half_rest]} = Editing.step(score, @ctx, [half_rest], :later)

    assert line(score) == [
             {0, 960, "C5"},
             {960, 960, :rest},
             {1920, 960, :rest},
             {2880, 960, "G4"},
             {3840, 1920, :rest},
             {5760, 960, "C5"},
             {6720, 960, :rest}
           ]

    # Beats 2–3 aren't allowed for a half rest, so it passes both items.
    {:ok, score, [^half_rest]} = Editing.step(score, @ctx, [half_rest], :later)

    assert line(score) |> Enum.drop(4) == [
             {3840, 960, "C5"},
             {4800, 960, :rest},
             {5760, 1920, :rest}
           ]

    assert rest_at(score, 5760) == half_rest

    # At the end of the score it stays where it is.
    assert {:ok, ^score, [^half_rest]} = Editing.step(score, @ctx, [half_rest], :later)
  end

  test "a note moves past the item beside it and jumps a bar line whole, never tied",
       %{score: score} do
    {score, d} = treble(score, 0, "D5", :half, 1920)

    {:ok, score, [^d]} = Editing.step(score, @ctx, [d], :later)

    # A half from beat 3 can't take one step (it would cross the bar line),
    # so it passes bar 2's quarter rest and G4, which move back.
    assert {3840, 1920, "D5"} in line(score)
    assert {2880, 960, "G4"} in line(score)
    assert tie_chain(score, d) == [d]

    {:ok, score, [^d]} = Editing.step(score, @ctx, [d], :earlier)
    assert {1920, 1920, "D5"} in line(score)
  end

  # E5 joins bar 2's C5 (beat 3) as a chord; ← takes it past G4.
  test "a chord moves as one", %{score: score} do
    {score, _e} = treble(score, 1, "E5", :quarter, 1920)
    chord = notes_at(score, 5760)

    {:ok, moved, ids} = Editing.step(score, @ctx, chord, :earlier)
    assert Enum.sort(ids) == Enum.sort(chord)
    assert {4800, 960, "C5"} in line(moved)
    assert {4800, 960, "E5"} in line(moved)
    assert {5760, 960, "G4"} in line(moved)
  end

  test "nothing selected, or the start of the score: nothing moves", %{score: score} do
    assert Editing.step(score, @ctx, [], :later) == {:ok, score, []}

    c = hd(notes_at(score, 0))
    assert {:ok, ^score, [^c]} = Editing.step(score, @ctx, [c], :earlier)
  end

  # The treble line as {start, ticks, pitch name or :rest}, in time order.
  defp line(score) do
    for entry <- Timeline.flatten(score, @ctx), entry.event.staff == :treble do
      {entry.start, entry.ticks, name(entry)}
    end
    |> Enum.sort()
  end

  defp name(%{kind: :rest}), do: :rest
  defp name(entry), do: Pitch.name(entry.event.step, entry.event.alter)

  defp notes_at(score, start) do
    for entry <- Timeline.flatten(score, @ctx),
        entry.kind == :note and entry.start == start,
        do: entry.event.id
  end

  defp rest_at(score, start) do
    Enum.find_value(Timeline.flatten(score, @ctx), fn entry ->
      entry.event.staff == :treble and entry.kind == :rest and entry.start == start and
        entry.event.id
    end)
  end

  defp treble(score, measure, spn, value, offset) do
    note!(score, @ctx, measure, spn, %{staff: :treble, value: value, offset: offset})
  end
end
