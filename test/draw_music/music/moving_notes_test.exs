defmodule DrawMusic.Music.MovingNotesTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Engraving.Staff
  alias DrawMusic.Music.{Context, Duration, Editing, Score, StaffCrossing}
  alias DrawMusicWeb.EditorCommands

  @ctx %Context{}
  @bar 3840

  describe "StaffCrossing.staff_for/2" do
    test "each staff keeps its half of the gap: the bass up to B4, the treble down to D3" do
      assert StaffCrossing.staff_for(:bass, 34) == :bass
      assert StaffCrossing.staff_for(:bass, 35) == :treble
      assert StaffCrossing.staff_for(:treble, 22) == :treble
      assert StaffCrossing.staff_for(:treble, 21) == :bass
    end

    test "those are the steps at the middle of the engraved gap" do
      half_gap = Staff.top(:bass) - Staff.height()
      treble_bottom = Staff.top_step(:treble) - 2 * Staff.height()

      assert StaffCrossing.staff_for(:treble, treble_bottom - half_gap) == :treble
      assert StaffCrossing.staff_for(:treble, treble_bottom - half_gap - 1) == :bass
      assert StaffCrossing.staff_for(:bass, Staff.top_step(:bass) + half_gap) == :bass
      assert StaffCrossing.staff_for(:bass, Staff.top_step(:bass) + half_gap + 1) == :treble
    end
  end

  describe "a moved note keeps its accidental" do
    test "F♯ up a step is G♯, down a step E♯" do
      {score, id} =
        note!(Score.new(), @ctx, 0, "F#4", %{staff: :treble, offset: 0, value: :quarter})

      {:ok, up} = Editing.move_steps(score, @ctx, [id], 1)
      assert notes(up) == [{0, 0, "G♯4", :quarter, 0}]

      {:ok, down} = Editing.move_steps(score, @ctx, [id], -1)
      assert notes(down) == [{0, 0, "E♯4", :quarter, 0}]
    end

    test "the key's own F♯ in G major goes to the key's G" do
      g_major = %Context{sf: 1}

      {score, id} =
        note!(Score.new(), g_major, 0, "F#4", %{staff: :treble, offset: 0, value: :quarter})

      {:ok, score} = Editing.move_steps(score, g_major, [id], 1)
      assert notes(score) == [{0, 0, "G4", :quarter, 0}]
    end

    test "a dragged note keeps it; a key held while dragging sets it" do
      {score, id} =
        note!(Score.new(), @ctx, 0, "Ab4", %{staff: :treble, offset: 0, value: :quarter})

      {:ok, kept, [^id]} = EditorCommands.drop_on_staff(id, :treble, 34, nil).(score, @ctx)
      assert notes(kept) == [{0, 0, "B♭4", :quarter, 0}]

      {:ok, sharp, [^id]} = EditorCommands.drop_on_staff(id, :treble, 34, 1).(score, @ctx)
      assert notes(sharp) == [{0, 0, "B♯4", :quarter, 0}]
    end
  end

  describe "a note moved past its staff's half of the gap changes staff" do
    # G3, a left-hand note on the bass staff (step 25).
    setup do
      {score, id} =
        note!(Score.new(), @ctx, 0, "G3", %{staff: :bass, offset: 0, value: :quarter, dots: 1})

      %{score: score, id: id}
    end

    test "a left-hand note stays on the bass staff past middle C, up to B4",
         %{score: score, id: id} do
      assert %{staff: :bass, step: 29} = score |> up(id, 4) |> note_of(id)
      assert %{staff: :bass, step: 34} = score |> up(id, 9) |> note_of(id)
    end

    test "past B4 it is a treble note, and both staves' rests are redone",
         %{score: score, id: id} do
      score = up(score, id, 10)

      assert %{staff: :treble, step: 35, dots: 1, offset: 0} = note_of(score, id)
      assert rests_on(score, :bass) == [{0, :whole}]
      assert rest_ticks(score, :treble) == @bar - 1440
    end

    test "a quarter then placed after it on the treble staff follows it",
         %{score: score, id: id} do
      score = up(score, id, 10)

      {score, _quarter} =
        note!(score, @ctx, 0, "E4", %{staff: :treble, offset: 1440, value: :quarter})

      treble = for n <- hd(score.measures).notes, n.staff == :treble, do: n.offset
      assert Enum.sort(treble) == [0, 1440]
      assert rest_ticks(score, :treble) == @bar - 1440 - 960
    end

    test "a right-hand note stays on the treble staff down to D3, then goes to the bass" do
      {score, id} = note!(Score.new(), @ctx, 0, "F3", %{staff: :treble, offset: 0, value: :half})

      {:ok, kept} = Editing.move_steps(score, @ctx, [id], -2)
      assert %{staff: :treble, step: 22} = note_of(kept, id)

      {:ok, crossed} = Editing.move_steps(score, @ctx, [id], -3)
      assert %{staff: :bass, step: 21} = note_of(crossed, id)
      assert rests_on(crossed, :treble) == [{0, :whole}]
    end

    test "by octave (Shift+↑) as well: one octave stays, two cross", %{score: score, id: id} do
      {:ok, one} = Editing.transpose_interval(score, @ctx, [id], 7, 12)
      assert %{staff: :bass} = note_of(one, id)

      {:ok, two} = Editing.transpose_interval(one, @ctx, [id], 7, 12)
      assert %{staff: :treble} = note_of(two, id)
    end

    test "a chord moved together stays a chord" do
      {score, g} = note!(Score.new(), @ctx, 0, "G3", %{staff: :bass, offset: 0, value: :quarter})
      {score, b} = note!(score, @ctx, 0, "B3", %{staff: :bass, offset: 0, value: :quarter})

      {:ok, score} = Editing.transpose_interval(score, @ctx, [g, b], 14, 24)

      assert %{staff: :treble, voice: voice} = note_of(score, g)
      assert %{staff: :treble, voice: ^voice} = note_of(score, b)
    end
  end

  describe "put on a staff on purpose (the menu)" do
    setup do
      {score, bass} =
        note!(Score.new(), @ctx, 0, "C3", %{staff: :bass, offset: 0, value: :quarter})

      {score, treble} = note!(score, @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})
      %{score: score, bass: bass, treble: treble}
    end

    test "a note keeps its pitch and joins a note of the same length there as a chord",
         %{score: score, bass: bass, treble: treble} do
      {:ok, score} = Editing.put_on_staff(score, @ctx, [treble], :bass)

      assert %{staff: :bass, step: 28, voice: voice} = note_of(score, treble)
      assert note_of(score, bass).voice == voice
    end

    test "a different length goes into another voice" do
      {score, bass} = note!(Score.new(), @ctx, 0, "C3", %{staff: :bass, offset: 0, value: :half})
      {score, treble} = note!(score, @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

      {:ok, score} = Editing.put_on_staff(score, @ctx, [treble], :bass)

      assert %{staff: :bass, voice: 1} = note_of(score, bass)
      assert %{staff: :bass, voice: 2} = note_of(score, treble)
    end

    test "however far from it, until the next move takes it back", %{score: score} do
      {score, e5} = note!(score, @ctx, 0, "E5", %{staff: :treble, offset: 960, value: :quarter})

      {:ok, score} = Editing.put_on_staff(score, @ctx, [e5], :bass)
      assert %{staff: :bass, step: 37} = note_of(score, e5)

      {:ok, score} = Editing.move_steps(score, @ctx, [e5], 1)
      assert %{staff: :treble, step: 38} = note_of(score, e5)
    end

    test "the same pitch already in the chord there is refused" do
      {score, _b} = note!(Score.new(), @ctx, 0, "B3", %{staff: :bass, offset: 0, value: :quarter})
      {score, b} = note!(score, @ctx, 0, "B3", %{staff: :treble, offset: 0, value: :quarter})

      assert Editing.put_on_staff(score, @ctx, [b], :bass) == {:error, :duplicate}
    end
  end

  defp note_of(score, id) do
    score.measures |> Enum.flat_map(& &1.notes) |> Enum.find(&(&1.id == id))
  end

  defp rest_ticks(score, staff) do
    for rest <- hd(score.measures).rests, rest.staff == staff, reduce: 0 do
      sum -> sum + Duration.ticks(rest.value, rest.dots)
    end
  end

  defp rests_on(score, staff) do
    for rest <- hd(score.measures).rests, rest.staff == staff, do: {rest.offset, rest.value}
  end

  defp up(score, id, times) do
    Enum.reduce(1..times, score, fn _step, score ->
      {:ok, score} = Editing.move_steps(score, @ctx, [id], 1)
      score
    end)
  end
end
