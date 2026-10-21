defmodule DrawMusic.MidiCodecTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Library.{Composition, Key, Version}
  alias DrawMusic.MidiCodec
  alias DrawMusic.Music.{Context, Editing, Pitch, Score}
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

    test "unreadable files are rejected", %{tmp_dir: dir} do
      assert import_binary("not a midi file", dir) == {:error, :invalid_midi}
    end
  end
end
