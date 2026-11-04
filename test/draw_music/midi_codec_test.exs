defmodule DrawMusic.MidiCodecTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Library.{Composition, Key, Version}
  alias DrawMusic.MidiCodec
  alias DrawMusic.Music.{Context, Editing, Pitch, Score, TempoChange}
  alias ExMidi.MidiFile

  @moduletag :tmp_dir

  defp import_binary(binary, dir, filename \\ "song.mid") do
    path = Path.join(dir, filename)
    File.write!(path, binary)
    MidiCodec.import(path, filename)
  end

  defp score_of(version_attrs) do
    %Version{number: 1}
    |> Version.changeset(version_attrs)
    |> Ecto.Changeset.apply_action!(:insert)
    |> Map.fetch!(:score)
  end

  test "a file exported here re-imports exactly", %{tmp_dir: dir} do
    ctx = %Context{sf: 1, time_num: 3, time_den: 4}
    {score, a} = note!(Score.new(2), ctx, 0, "F#4", %{staff: :treble, offset: 960, value: :half})
    {score, b} = note!(score, ctx, 1, "F#4", %{staff: :treble, offset: 0, value: :quarter})
    {score, _id} = note!(score, ctx, 0, "G2", %{staff: :bass, offset: 0, value: :half, dots: 1})
    {:ok, score} = Editing.tie(score, ctx, a, b)

    composition = %Composition{name: "Waltz", composer: "J. Doe"}
    key = %Key{sf: 1, mode: :major, composition: composition}
    version = %Version{number: 1, key: key, time_num: 3, time_den: 4, tempo_bpm: 90, score: score}

    {:ok, binary} = MidiCodec.export(version)
    {:ok, imported} = import_binary(binary, dir)

    assert imported.name == "Waltz"
    assert imported.composition.composer == "J. Doe"
    assert imported.key.sf == 1
    assert %{time_num: 3, time_den: 4, tempo_bpm: 90} = imported.version

    round_tripped = score_of(imported.version)
    assert notes(round_tripped) == notes(score)
    assert tie_chain(round_tripped, a) == [a, b]
  end

  # Other programs read the tempo events, not our JSON: the start, each
  # mark, and a rit. as a step on each beat ending on its last tempo.
  test "tempo changes are written as tempo events", %{tmp_dir: dir} do
    tempos = [
      %TempoChange{tick: 960, bpm: 60},
      %TempoChange{tick: 1920, bpm: 60, to_tick: 3840, to_bpm: 40}
    ]

    composition = %Composition{name: "Slowing"}
    key = %Key{sf: -1, mode: :minor, composition: composition}
    score = %{Score.new() | tempos: tempos}
    version = %Version{number: 1, key: key, time_num: 4, time_den: 4, tempo_bpm: 90, score: score}

    {:ok, binary} = MidiCodec.export(version)
    path = Path.join(dir, "out.mid")
    File.write!(path, binary)
    {:midi_file, 1, 960, [{:track, conductor} | _staves]} = MidiFile.read(path)

    {tempo_events, _tick} =
      Enum.flat_map_reduce(conductor, 0, fn {name, delta, values}, tick ->
        tick = tick + delta

        case {name, values} do
          {:tempo, [mpq]} -> {[{tick, round(60_000_000 / mpq)}], tick}
          _other -> {[], tick}
        end
      end)

    assert tempo_events == [{0, 90}, {960, 60}, {1920, 60}, {2880, 50}, {3840, 40}]
    assert Enum.any?(conductor, &match?({:key_signature, 0, [<<-1::signed-8, 1>>]}, &1))
  end

  describe "plain MIDI files" do
    # 480 ticks per quarter. Treble: C5 then D5, played legato (overlapping
    # by 20 ticks). Bass: C3 held for a half note under eighths E3, G3.
    defp plain_file do
      treble = [
        {:on, 0, [0, 72, 80]},
        {:on, 240, [0, 74, 80]},
        {:off, 20, [0, 72, 0]},
        {:off, 220, [0, 74, 0]},
        {:track_end, 0, []}
      ]

      bass = [
        {:on, 0, [1, 48, 80]},
        {:on, 0, [1, 52, 80]},
        {:off, 240, [1, 52, 0]},
        {:on, 0, [1, 55, 80]},
        {:off, 240, [1, 55, 0]},
        {:off, 480, [1, 48, 0]},
        {:track_end, 0, []}
      ]

      {:midi_file, 1, 480, [{:track, treble}, {:track, bass}]}
    end

    test "held notes keep their length in another voice; legato overlaps are trimmed", %{
      tmp_dir: dir
    } do
      path = Path.join(dir, "Plain Song.mid")
      :ok = MidiFile.write(plain_file(), path)
      {:ok, imported} = MidiCodec.import(path, "Plain Song.mid")

      assert imported.name == "Plain Song"

      placed =
        for m <- imported.version.score.measures, n <- m.notes do
          {n.staff, n.voice, n.offset, Pitch.name(n.step, n.alter), n.value}
        end

      assert Enum.sort(placed) == [
               {:bass, 1, 0, "E3", :eighth},
               {:bass, 1, 480, "G3", :eighth},
               {:bass, 2, 0, "C3", :half},
               {:treble, 1, 0, "C5", :eighth},
               {:treble, 1, 480, "D5", :eighth}
             ]
    end

    # Tracks past the first two are split at middle C, so their low notes
    # share the bass staff with the second track's: they must share its
    # voices too, not reuse voice 1 at the same time.
    test "notes from several tracks on one staff get separate voices", %{tmp_dir: dir} do
      treble = [{:on, 0, [0, 72, 80]}, {:off, 480, [0, 72, 0]}, {:track_end, 0, []}]
      bass = [{:on, 0, [1, 52, 80]}, {:off, 960, [1, 52, 0]}, {:track_end, 0, []}]
      pedal = [{:on, 0, [2, 43, 80]}, {:off, 480, [2, 43, 0]}, {:track_end, 0, []}]

      path = Path.join(dir, "Organ.mid")

      :ok =
        MidiFile.write(
          {:midi_file, 1, 480, [{:track, treble}, {:track, bass}, {:track, pedal}]},
          path
        )

      {:ok, imported} = MidiCodec.import(path, "Organ.mid")

      bass_voices =
        for m <- imported.version.score.measures, n <- m.notes, n.staff == :bass do
          {Pitch.name(n.step, n.alter), n.voice}
        end

      assert [{"E3", e3}, {"G2", g2}] = Enum.sort(bass_voices)
      assert e3 != g2

      ctx = %Context{time_num: imported.version.time_num, time_den: imported.version.time_den}
      assert {:ok, _score} = Editing.rebar_to(imported.version.score, ctx, ctx)
    end

    # A D minor scale with its raised seventh, two octaves up and down.
    defp d_minor_track(key_signature) do
      keys = [62, 64, 65, 67, 69, 70, 73, 74, 73, 70, 69, 67, 65, 64, 62, 62, 57, 62, 65, 69]

      notes =
        Enum.flat_map(keys, fn key -> [{:on, 0, [0, key, 80]}, {:off, 480, [0, key, 0]}] end)

      key_event = if key_signature, do: [{:key_signature, 0, [key_signature]}], else: []
      key_event ++ notes ++ [{:track_end, 0, []}]
    end

    defp import_track(dir, events) do
      path = Path.join(dir, "Key.mid")
      :ok = MidiFile.write({:midi_file, 1, 480, [{:track, events}]}, path)
      {:ok, imported} = MidiCodec.import(path, "Key.mid")
      imported
    end

    test "the key comes from the notes when the file says C major or nothing", %{tmp_dir: dir} do
      assert import_track(dir, d_minor_track(<<0, 0>>)).key == %{sf: -1, mode: :minor}
      assert import_track(dir, d_minor_track(nil)).key == %{sf: -1, mode: :minor}
    end

    test "a file's own key with the notes' signature keeps its major or minor", %{tmp_dir: dir} do
      # F major shares D minor's one flat: the author's word stands.
      assert import_track(dir, d_minor_track(<<-1::signed-8, 0>>)).key == %{sf: -1, mode: :major}
      # E minor doesn't fit the notes: they win.
      assert import_track(dir, d_minor_track(<<1, 1>>)).key == %{sf: -1, mode: :minor}
    end

    # 480 ticks a quarter in the file, 960 here. 100 BPM to start, a mark to
    # 60 on beat 2 (given twice), then three beats on a steady slowing, one
    # step a beat.
    test "tempo changes become marks, and runs of small steps a rit.", %{tmp_dir: dir} do
      mpq = &round(60_000_000 / &1)

      events =
        [
          {:tempo, 0, [mpq.(100)]},
          {:tempo, 480, [mpq.(60)]},
          {:tempo, 0, [mpq.(60)]},
          {:tempo, 1440, [mpq.(58)]},
          {:tempo, 480, [mpq.(55)]},
          {:tempo, 480, [mpq.(52)]},
          {:tempo, 480, [mpq.(50)]}
        ] ++ d_minor_track(nil)

      imported = import_track(dir, events)

      assert imported.version.tempo_bpm == 100

      assert [
               %TempoChange{tick: 960, bpm: 60, to_tick: nil},
               %TempoChange{tick: 3840, bpm: 58, to_tick: 6720, to_bpm: 50}
             ] = imported.version.score.tempos

      assert Enum.all?(imported.version.score.tempos, &is_binary(&1.id))
    end

    test "unreadable files are rejected", %{tmp_dir: dir} do
      assert import_binary("not a midi file", dir) == {:error, :invalid_midi}
    end
  end
end
