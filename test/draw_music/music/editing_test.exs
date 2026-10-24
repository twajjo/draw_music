defmodule DrawMusic.Music.EditingTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Music.{Context, Editing, Score, Transpose}

  @ctx %Context{}

  defp place(score, index, spn, attrs),
    do:
      Editing.place_note(score, @ctx, index, placement(spn, Map.merge(%{staff: :treble}, attrs)))

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

    test "fill_rests fills voice 1 of each staff and any other voice in use, on the beats" do
      {score, _id} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

      {score, _id} =
        note!(score, @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :half, voice: 2})

      rests =
        for r <- hd(Editing.fill_rests(score, @ctx).measures).rests,
            do: {r.staff, r.voice, r.offset, r.value, r.dots}

      assert Enum.sort(rests) == [
               {:bass, 1, 0, :whole, 0},
               {:treble, 1, 960, :quarter, 0},
               {:treble, 1, 1920, :half, 0},
               {:treble, 2, 1920, :half, 0}
             ]
    end

    test "move_to_staff moves a note to the other staff, leaving a gap on the first" do
      {score, id} =
        note!(Score.new(), @ctx, 0, "G3", %{staff: :treble, offset: 960, value: :half})

      {:ok, score, new_id} = Editing.move_to_staff(score, @ctx, id, :bass, 25)
      [note] = hd(score.measures).notes

      assert {note.id, note.staff, note.step, note.offset, note.value} ==
               {new_id, :bass, 25, 960, :half}
    end

    test "move_to_staff on the note's own staff just moves it, keeping its id" do
      {score, id} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

      {:ok, score, ^id} = Editing.move_to_staff(score, @ctx, id, :treble, 30)
      assert [%{id: ^id, staff: :treble, step: 30}] = hd(score.measures).notes
    end

    test "move_to_staff joins a note already on the other staff as a second voice or chord" do
      {score, bass} =
        note!(Score.new(), @ctx, 0, "C3", %{staff: :bass, offset: 0, value: :quarter})

      {score, id} = note!(score, @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

      {:ok, score, new_id} = Editing.move_to_staff(score, @ctx, id, :bass, 23)
      ids = for n <- hd(score.measures).notes, n.staff == :bass, do: n.id

      assert Enum.sort(ids) == Enum.sort([bass, new_id])
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

  describe "insert_time/5" do
    test "shifts later events on that staff only" do
      {score, _id} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

      {score, _id} = note!(score, @ctx, 0, "E4", %{staff: :treble, offset: 960, value: :quarter})
      {score, _id} = note!(score, @ctx, 0, "C3", %{staff: :bass, offset: 0, value: :whole})

      {:ok, score} = Editing.insert_time(score, @ctx, 960, 480, :treble)

      assert notes(score) == [
               {0, 0, "C3", :whole, 0},
               {0, 0, "C4", :quarter, 0},
               {0, 1440, "E4", :quarter, 0}
             ]
    end

    test "splits a note sounding across the point and drops its tie" do
      {score, id} = note!(Score.new(), @ctx, 0, "G4", %{staff: :treble, offset: 0, value: :half})

      {:ok, score} = Editing.insert_time(score, @ctx, 960, 960, :treble)

      assert notes(score) == [{0, 0, "G4", :quarter, 0}, {0, 1920, "G4", :quarter, 0}]
      assert tie_chain(score, id) == [id]
    end

    test "appends bars when pushed past the end" do
      {score, id} =
        note!(Score.new(1), @ctx, 0, "G4", %{staff: :treble, offset: 0, value: :whole})

      {:ok, score} = Editing.insert_time(score, @ctx, 0, 960, :treble)

      assert length(score.measures) == 2
      assert notes(score) == [{0, 960, "G4", :half, 1}, {1, 0, "G4", :quarter, 0}]
      assert length(tie_chain(score, id)) == 2
    end
  end

  defp rests(score) do
    for {m, i} <- Enum.with_index(score.measures),
        r <- m.rests,
        do: {i, r.offset, r.value, r.dots}
  end

  describe "split/3" do
    test "a note becomes two tied halves" do
      {score, id} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

      {:ok, score, [^id, second]} = Editing.split(score, @ctx, id)

      assert notes(score) == [{0, 0, "C4", :eighth, 0}, {0, 480, "C4", :eighth, 0}]
      assert tie_chain(score, id) == [id, second]
    end

    test "a dotted value loses a dot and keeps the remainder" do
      {score, id} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter, dots: 1})

      {:ok, score, _ids} = Editing.split(score, @ctx, id)
      assert notes(score) == [{0, 0, "C4", :quarter, 0}, {0, 960, "C4", :eighth, 0}]
    end

    test "a rest becomes two rests" do
      {:ok, score, id} =
        Editing.place_rest(
          Score.new(),
          @ctx,
          0,
          placement(%{staff: :treble, offset: 0, value: :quarter})
        )

      {:ok, score, _ids} = Editing.split(score, @ctx, id)
      assert rests(score) == [{0, 0, :eighth, 0}, {0, 480, :eighth, 0}]
    end

    test "a 64th cannot be split" do
      {score, id} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :sixty_fourth})

      assert Editing.split(score, @ctx, id) == {:error, :unrepresentable}
    end
  end

  describe "set_value/5" do
    test "lengthens a note when there is room" do
      {score, id} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

      {:ok, score} = Editing.set_value(score, @ctx, id, :half, 0)
      assert notes(score) == [{0, 0, "C4", :half, 0}]
    end

    test "refuses to overfill the bar" do
      {score, id} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 2880, value: :quarter})

      assert Editing.set_value(score, @ctx, id, :half, 0) == {:error, :measure_full}
    end

    test "refuses to run into the next note of the voice" do
      {score, id} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

      {score, _id} = note!(score, @ctx, 0, "E4", %{staff: :treble, offset: 960, value: :quarter})

      assert Editing.set_value(score, @ctx, id, :half, 0) == {:error, :overlap}
    end

    @tag timeout: 1_000
    test "rejects more than two dots rather than retrying forever" do
      {score, id} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

      assert_raise FunctionClauseError, fn -> Editing.set_value(score, @ctx, [id], :half, 3) end
    end
  end

  describe "to_rest/3 and to_note/5" do
    test "a note becomes a rest of the same length, losing its ties" do
      {score, a} =
        note!(Score.new(), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

      {score, b} = note!(score, @ctx, 0, "C4", %{staff: :treble, offset: 960, value: :quarter})
      {:ok, score} = Editing.tie(score, @ctx, a, b)

      {:ok, score, _rest_id} = Editing.to_rest(score, @ctx, b)

      assert notes(score) == [{0, 0, "C4", :quarter, 0}]
      assert rests(score) == [{0, 960, :quarter, 0}]
      assert tie_chain(score, a) == [a]
    end

    test "a rest becomes a note on the given step" do
      {:ok, score, id} =
        Editing.place_rest(
          Score.new(),
          @ctx,
          0,
          placement(%{staff: :treble, offset: 960, value: :half})
        )

      {step, alter} = pitch!("E4")
      {:ok, score, _note_id} = Editing.to_note(score, @ctx, id, step, alter)

      assert notes(score) == [{0, 960, "E4", :half, 0}]
      assert rests(score) == []
    end
  end

  defp q(score, offset, spn, attrs \\ %{}) do
    note!(
      score,
      @ctx,
      0,
      spn,
      Map.merge(%{staff: :treble, offset: offset, value: :quarter}, attrs)
    )
  end

  describe "delete/3" do
    setup do
      {s, c} = q(Score.new(), 0, "C4")
      {s, d} = q(s, 960, "D4")
      {s, _e} = q(s, 1920, "E4")
      {s, _bass} = note!(s, @ctx, 0, "C3", %{staff: :bass, offset: 0, value: :whole})
      %{score: s, c: c, d: d}
    end

    test "closes the gap on that staff only", %{score: score, d: d} do
      {:ok, score} = Editing.delete(score, @ctx, [d])

      assert notes(score) == [
               {0, 0, "C3", :whole, 0},
               {0, 0, "C4", :quarter, 0},
               {0, 960, "E4", :quarter, 0}
             ]
    end

    test "closes a gap left by several events", %{score: score, c: c, d: d} do
      {:ok, score} = Editing.delete(score, @ctx, [c, d])
      assert {0, 0, "E4", :quarter, 0} in notes(score)
    end

    test "time another voice still sounds is not a gap", %{score: score, c: c} do
      {score, _v2} = q(score, 0, "G4", %{value: :half, voice: 2})
      {:ok, score} = Editing.delete(score, @ctx, [c])

      assert {0, 960, "D4", :quarter, 0} in notes(score)
    end
  end

  describe "transposing" do
    test "by semitones, spelled for the key" do
      {s, id} = q(Score.new(), 0, "C4")
      {:ok, up} = Editing.transpose_chromatic(s, @ctx, [id], 1)
      assert [{0, 0, "C♯4", :quarter, 0}] = notes(up)

      {:ok, flat_key} = Editing.transpose_chromatic(s, %Context{sf: -1}, [id], 1)
      assert [{0, 0, "D♭4", :quarter, 0}] = notes(flat_key)
    end

    test "by an exact interval" do
      {s, id} = q(Score.new(), 0, "C4")
      {:ok, third_up} = Editing.transpose_interval(s, @ctx, [id], 2, 4)
      assert [{0, 0, "E4", :quarter, 0}] = notes(third_up)

      {:ok, minor_third_down} = Editing.transpose_interval(s, @ctx, [id], -2, -3)
      assert [{0, 0, "A3", :quarter, 0}] = notes(minor_third_down)

      {s, fs} = q(Score.new(), 0, "F#4")
      {:ok, major_third} = Editing.transpose_interval(s, @ctx, [fs], 2, 4)
      assert [{0, 0, "A♯4", :quarter, 0}] = notes(major_third)
    end

    test "refuses to leave the piano's range" do
      {s, id} = q(Score.new(), 0, "C8")
      assert Editing.transpose_chromatic(s, @ctx, [id], 1) == {:error, :out_of_range}
    end
  end

  describe "reverse/3" do
    test "plays the selection backwards in its own span" do
      {s, c} = q(Score.new(), 0, "C4")
      {s, d} = note!(s, @ctx, 0, "D4", %{staff: :treble, offset: 960, value: :eighth})
      {s, e} = q(s, 1440, "E4")

      {:ok, s} = Editing.reverse(s, @ctx, [c, d, e])

      assert notes(s) == [
               {0, 0, "E4", :quarter, 0},
               {0, 960, "D4", :eighth, 0},
               {0, 1440, "C4", :quarter, 0}
             ]
    end

    test "ties inside the selection still point forward" do
      {s, a} = q(Score.new(), 0, "C4")
      {s, b} = q(s, 960, "C4")
      {:ok, s} = Editing.tie(s, @ctx, a, b)

      {:ok, s} = Editing.reverse(s, @ctx, [a, b])
      assert tie_chain(s, b) == [b, a]
    end
  end

  describe "review fixes" do
    test "rebar_to handles much shorter bars" do
      {s, _id} = note!(Score.new(4), @ctx, 3, "C4", %{staff: :treble, offset: 0, value: :eighth})
      assert {:ok, s} = Editing.rebar_to(s, @ctx, %Context{time_num: 1, time_den: 8})
      assert length(s.measures) == 32
    end

    test "the pickup bar can't be deleted" do
      ctx = %Context{pickup_ticks: 960}
      assert Editing.delete_measure(Score.new(2), ctx, 0) == {:error, :pickup_bar}
      assert {:ok, _score} = Editing.delete_measure(Score.new(3), ctx, 1)
    end

    test "inserting a bar drops ties it separates" do
      {s, a} = q(Score.new(2), 2880, "C4")
      {s, b} = note!(s, @ctx, 1, "C4", %{staff: :treble, offset: 0, value: :quarter})
      {:ok, s} = Editing.tie(s, @ctx, a, b)

      {:ok, s} = Editing.insert_measure(s, @ctx, 1)
      assert tie_chain(s, a) == [a]
    end

    test "chord_ids finds the whole chord" do
      {:ok, s, ids} =
        Editing.place_chord(
          Score.new(),
          @ctx,
          0,
          placement(%{staff: :treble, offset: 0, value: :quarter}),
          [
            pitch!("C4"),
            pitch!("E4")
          ]
        )

      assert Enum.sort(Editing.chord_ids(s, @ctx, hd(ids))) == Enum.sort(ids)
    end

    test "set_value and split change a whole chord" do
      {:ok, s, ids} =
        Editing.place_chord(
          Score.new(),
          @ctx,
          0,
          placement(%{staff: :treble, offset: 0, value: :quarter}),
          [
            pitch!("C4"),
            pitch!("E4")
          ]
        )

      {:ok, half} = Editing.set_value(s, @ctx, ids, :half, 0)
      assert Enum.map(notes(half), &elem(&1, 3)) == [:half, :half]

      {:ok, split, _ids} = Editing.split(s, @ctx, ids)
      assert length(notes(split)) == 4
    end

    test "to_rest turns a whole chord into one rest" do
      {:ok, s, ids} =
        Editing.place_chord(
          Score.new(),
          @ctx,
          0,
          placement(%{staff: :treble, offset: 0, value: :quarter}),
          [
            pitch!("C4"),
            pitch!("E4")
          ]
        )

      {:ok, s, _rest} = Editing.to_rest(s, @ctx, ids)
      assert notes(s) == []
      assert rests(s) == [{0, 0, :quarter, 0}]
    end
  end

  describe "rebar_to/3" do
    test "keeps events' times and re-flows them into the new bars" do
      {score, id} =
        note!(Score.new(), @ctx, 0, "G4", %{staff: :treble, offset: 1920, value: :half})

      {:ok, score} = Editing.rebar_to(score, @ctx, %Context{time_num: 3, time_den: 4})

      assert notes(score) == [{0, 1920, "G4", :quarter, 0}, {1, 0, "G4", :quarter, 0}]
      assert length(tie_chain(score, id)) == 2
    end
  end
end
