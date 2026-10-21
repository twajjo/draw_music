defmodule DrawMusic.Music.EditingTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Music.{Context, Editing, Score, Transpose}

  @ctx %Context{}

  defp place(score, index, spn, attrs) do
    {step, alter} = pitch!(spn)

    Editing.place_note(
      score,
      @ctx,
      index,
      Map.merge(%{staff: :treble, step: step, alter: alter}, attrs)
    )
  end

  defp voices(score) do
    for m <- score.measures, n <- m.notes, do: {n.offset, n.value, n.voice}
  end

  describe "placing" do
    test "a note fills its measure; overfilling or a missing measure is an error" do
      {score, _id} =
        note!(Score.new(2), @ctx, 1, "C4", %{staff: :treble, offset: 960, value: :half})

      assert notes(score) == [{1, 960, "C4", :half, 0}]

      assert place(score, 0, "D4", %{offset: 960, value: :whole}) == {:error, :measure_full}
      assert place(score, 2, "D4", %{offset: 0, value: :quarter}) == {:error, :no_such_measure}
    end

    test "notes outside A0–C8 are rejected" do
      assert place(Score.new(), 0, "C8", %{offset: 0, value: :quarter, alter: 1}) ==
               {:error, :out_of_range}
    end

    test "overlapping notes go to the next free voice; a fifth is refused" do
      score =
        Enum.reduce([:whole, :half, :quarter, :eighth], Score.new(), fn value, score ->
          {score, _id} = note!(score, @ctx, 0, "C4", %{staff: :treble, offset: 0, value: value})
          score
        end)

      assert Enum.sort(voices(score)) ==
               [{0, :eighth, 4}, {0, :half, 2}, {0, :quarter, 3}, {0, :whole, 1}]

      assert place(score, 0, "C4", %{offset: 0, value: :sixteenth}) == {:error, :overlap}
    end

    test "in one voice, same start and length make a chord, but not on the same step" do
      {score, _id} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

      assert {:ok, chord, _id} = place(score, 0, "E4", %{offset: 0, value: :quarter, voice: 1})
      assert Enum.map(notes(chord), &elem(&1, 2)) == ["C4", "E4"]

      assert place(score, 0, "C4", %{offset: 0, value: :quarter, voice: 1}) ==
               {:error, :duplicate}

      assert place(score, 0, "E4", %{offset: 480, value: :quarter, voice: 1}) ==
               {:error, :overlap}
    end

    test "voices on different staves never collide" do
      {score, _id} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :whole})

      {score, _id} = note!(score, @ctx, 0, "C3", %{staff: :bass, offset: 0, value: :whole})
      assert Enum.map(voices(score), &elem(&1, 2)) == [1, 1]
    end
  end

  describe "moving" do
    test "shifting across a bar line splits the note into a tie, adding measures as needed" do
      {score, id} =
        note!(Score.new(), @ctx, 0, "G4", %{staff: :treble, offset: 1920, value: :half})

      {:ok, score} = Editing.shift(score, @ctx, [id], 1)

      assert notes(score) == [{0, 2880, "G4", :quarter, 0}, {1, 0, "G4", :quarter, 0}]
      assert length(tie_chain(score, id)) == 2
    end

    test "shifting before the start is an error" do
      {score, id} =
        note!(Score.new(), @ctx, 0, "G4", %{staff: :treble, offset: 0, value: :quarter})

      assert Editing.shift(score, @ctx, [id], -1) == {:error, :before_start}
    end

    test "moving by steps lands on the key's own notes" do
      g_major = %Context{sf: 1}

      {score, id} =
        note!(Score.new(), g_major, 0, "E4", %{staff: :treble, offset: 0, value: :quarter})

      {:ok, score} = Editing.move_steps(score, g_major, [id], 1)
      assert notes(score) == [{0, 0, "F♯4", :quarter, 0}]
    end
  end

  describe "ties" do
    setup do
      {score, a} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

      {score, b} = note!(score, @ctx, 0, "C4", %{staff: :treble, offset: 960, value: :quarter})
      {score, c} = note!(score, @ctx, 0, "D4", %{staff: :treble, offset: 1920, value: :quarter})
      %{score: score, a: a, b: b, c: c}
    end

    test "join equal pitches that touch, given in either order", %{score: score, a: a, b: b, c: c} do
      assert {:ok, tied} = Editing.tie(score, @ctx, b, a)
      assert tie_chain(tied, a) == [a, b]
      assert Editing.tie(score, @ctx, b, c) == {:error, :not_tieable}
      assert Editing.tie(score, @ctx, a, c) == {:error, :not_tieable}
    end

    test "are removed by edits that break them", %{score: score, a: a, b: b} do
      {:ok, tied} = Editing.tie(score, @ctx, a, b)
      {:ok, moved} = Editing.move_steps(tied, @ctx, [b], 1)
      assert tie_chain(moved, a) == [a]
    end
  end

  describe "measures, clipboard and rests" do
    test "the last measure cannot be deleted" do
      assert Editing.delete_measure(Score.new(), @ctx, 0) == {:error, :last_measure}
    end

    test "paste copies events with fresh ids at a new position" do
      {score, a} =
        note!(Score.new(2), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

      {score, b} = note!(score, @ctx, 0, "E4", %{staff: :treble, offset: 960, value: :quarter})

      clipboard = Editing.copy(score, @ctx, [a, b])
      {:ok, pasted, ids} = Editing.paste(score, @ctx, clipboard, 3840 + 960)

      assert Enum.drop(notes(pasted), 2) == [
               {1, 960, "C4", :quarter, 0},
               {1, 1920, "E4", :quarter, 0}
             ]

      assert MapSet.disjoint?(MapSet.new(ids), MapSet.new([a, b]))
    end

    test "fill_rests fills voice 1 of each staff and any other voice in use" do
      {score, _id} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

      {score, _id} =
        note!(score, @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :half, voice: 2})

      rests =
        for r <- hd(Editing.fill_rests(score, @ctx).measures).rests,
            do: {r.staff, r.voice, r.offset, r.value, r.dots}

      assert Enum.sort(rests) == [
               {:bass, 1, 0, :whole, 0},
               {:treble, 1, 960, :half, 1},
               {:treble, 2, 1920, :half, 0}
             ]
    end
  end

  describe "Transpose.to_key/4" do
    setup do
      {score, _id} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

      {score, _id} = note!(score, @ctx, 0, "F4", %{staff: :treble, offset: 960, value: :quarter})

      {score, _id} =
        note!(score, @ctx, 0, "C#5", %{staff: :treble, offset: 1920, value: :quarter})

      %{score: score}
    end

    test "moves tonic to tonic by the nearest way, keeping chromatic notes chromatic", %{
      score: score
    } do
      {:ok, down} = Transpose.to_key(score, {0, :major}, {1, :major})
      assert Enum.map(notes(down), &elem(&1, 2)) == ["G3", "C4", "G♯4"]

      {:ok, up} = Transpose.to_key(score, {0, :major}, {1, :major}, :up)
      assert Enum.map(notes(up), &elem(&1, 2)) == ["G4", "C5", "G♯5"]
    end

    test "refuses to leave the piano's range" do
      {score, _id} =
        note!(Score.new(), @ctx, 0, "B0", %{staff: :bass, offset: 0, value: :quarter})

      assert Transpose.to_key(score, {0, :major}, {-1, :major}, :down) == {:error, :out_of_range}
    end
  end
end
