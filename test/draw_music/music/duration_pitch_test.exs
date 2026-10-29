defmodule DrawMusic.Music.DurationPitchTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Music.{Context, Duration, Pitch}

  describe "Duration" do
    test "dots add half, then a quarter, of the base value" do
      assert Duration.ticks(:quarter) == 960
      assert Duration.ticks(:quarter, 1) == 1440
      assert Duration.ticks(:quarter, 2) == 1680
      assert Duration.ticks(:sixty_fourth, 2) == 105
      assert Duration.ticks(:hundred_twenty_eighth, 1) == 45
      assert Duration.ticks(:two_hundred_fifty_sixth) == 15
    end

    test "a 128th takes one dot at most and a 256th none: no fractions of a tick" do
      assert Duration.dots_allowed?(:sixty_fourth, 2)
      assert Duration.dots_allowed?(:hundred_twenty_eighth, 1)
      refute Duration.dots_allowed?(:hundred_twenty_eighth, 2)
      refute Duration.dots_allowed?(:two_hundred_fifty_sixth, 1)
    end

    test "decompose/1 splits lengths into note values, longest first" do
      assert Duration.decompose(1920) == {:ok, [half: 0]}
      assert Duration.decompose(2400) == {:ok, [half: 0, eighth: 0]}
      assert Duration.decompose(150) == {:ok, [{:sixty_fourth, 1}, {:sixty_fourth, 0}]}
    end

    test "decompose/1 reaches for 128ths and 256ths only when nothing longer adds up" do
      assert Duration.decompose(15) == {:ok, [two_hundred_fifty_sixth: 0]}
      assert Duration.decompose(45) == {:ok, [hundred_twenty_eighth: 1]}
      assert Duration.decompose(135) == {:ok, [thirty_second: 0, two_hundred_fifty_sixth: 0]}
    end

    test "decompose/1 rejects lengths no values add up to" do
      for ticks <- [7, 20, 100] do
        assert Duration.decompose(ticks) == {:error, :unrepresentable}
      end
    end

    test "only eighths and shorter are beamable" do
      refute Duration.beamable?(:quarter)
      assert Duration.flags(:eighth) == 1
      assert Duration.flags(:sixty_fourth) == 4
    end
  end

  describe "Pitch" do
    test "scientific pitch notation round-trips and maps to MIDI" do
      for {spn, midi} <- [{"A0", 21}, {"B3", 59}, {"C4", 60}, {"A4", 69}, {"C8", 108}] do
        {:ok, {step, alter}} = Pitch.parse(spn)
        assert Pitch.midi(step, alter) == midi
        assert Pitch.name(step, alter) == spn
      end
    end

    test "parse/1 accepts ASCII and Unicode accidentals and rejects bad names" do
      assert Pitch.parse("Bb3") == Pitch.parse("B♭3")
      assert Pitch.parse("C##4") == Pitch.parse("C𝄪4")
      assert {:ok, {_step, 0}} = Pitch.parse("F♮4")
      assert Pitch.parse("H4") == {:error, :invalid_pitch}
      assert Pitch.parse("C") == {:error, :invalid_pitch}
    end

    test "B♯3 and C♭4 cross the octave boundary correctly" do
      {:ok, {step, alter}} = Pitch.parse("B#3")
      assert Pitch.midi(step, alter) == 60
      {:ok, {step, alter}} = Pitch.parse("Cb4")
      assert Pitch.midi(step, alter) == 59
    end

    test "A4 is 440 Hz and octaves double" do
      assert Pitch.frequency(69) == 440.0
      assert_in_delta Pitch.frequency(81), 880.0, 1.0e-9
      assert_in_delta Pitch.frequency(60), 261.6256, 1.0e-4
    end

    test "key signatures alter letters in the order of sharps and flats" do
      # D major: F♯ C♯; B♭ major: B♭ E♭
      assert Enum.map(0..6, &Pitch.key_alter(2, &1)) == [1, 0, 0, 1, 0, 0, 0]
      assert Enum.map(0..6, &Pitch.key_alter(-2, &1)) == [0, 0, -1, 0, 0, 0, -1]
    end

    test "tonic/2 of major and relative minor keys" do
      names = fn {letter, _pc} -> Enum.at(~w(C D E F G A B), letter) end
      assert names.(Pitch.tonic(3, :major)) == "A"
      assert names.(Pitch.tonic(3, :minor)) == "F"
      assert names.(Pitch.tonic(-3, :minor)) == "C"
    end

    test "spell/2 prefers the key's notes, then naturals, then sharps or flats by key" do
      spell = fn midi, sf ->
        midi |> Pitch.spell(sf) |> then(fn {s, a} -> Pitch.name(s, a) end)
      end

      assert spell.(61, 0) == "C♯4"
      assert spell.(61, -1) == "D♭4"
      assert spell.(65, 1) == "F4"
      assert spell.(66, 1) == "F♯4"
      assert spell.(60, 7) == "B♯3"
      assert spell.(59, -7) == "C♭4"
    end
  end

  describe "Context" do
    test "measure length, beat unit and beam grouping follow the time signature" do
      six_eight = %Context{time_num: 6, time_den: 8}
      assert Context.measure_ticks(six_eight) == 2880
      assert Context.beat_ticks(six_eight) == 480
      assert Context.beam_group_ticks(six_eight) == 1440

      three_four = %Context{time_num: 3, time_den: 4}
      refute Context.compound?(three_four)
      assert Context.beam_group_ticks(three_four) == 960
    end

    test "a pickup shortens only the first measure" do
      ctx = %Context{time_num: 4, time_den: 4, pickup_ticks: 960}
      assert Context.capacity(ctx, 0) == 960
      assert Context.capacity(ctx, 1) == 3840
      assert Context.span(ctx, 3) == 960 + 2 * 3840
    end
  end
end
