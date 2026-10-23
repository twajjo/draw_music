defmodule DrawMusicWeb.InstrumentSourceTest do
  # Points the app's samples_dir at a temp dir, so not async.
  use ExUnit.Case, async: false

  alias DrawMusic.Samples.Manifest
  alias DrawMusicWeb.InstrumentSource

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    previous = Application.fetch_env!(:draw_music, :samples_dir)
    Application.put_env(:draw_music, :samples_dir, dir)
    on_exit(fn -> Application.put_env(:draw_music, :samples_dir, previous) end)
    %{dir: dir}
  end

  defp entry, do: %{bytes: 1, fetched_at: DateTime.utc_now()}

  test "nothing installed plays the synth" do
    assert %InstrumentSource{kind: :synth, url: nil, name: "Flute"} =
             InstrumentSource.for_program(73)
  end

  test "an installed soundfont is served from /samples", %{dir: dir} do
    Manifest.write(%Manifest{soundfonts: %{"flute" => entry()}}, dir)

    assert %InstrumentSource{kind: :soundfont, url: "/samples/musyngkite/flute-mp3.js"} =
             InstrumentSource.for_program(73)
  end

  test "the piano prefers the Splendid set, else its soundfont", %{dir: dir} do
    Manifest.write(%Manifest{soundfonts: %{"acoustic_grand_piano" => entry()}}, dir)
    assert %InstrumentSource{kind: :soundfont} = InstrumentSource.for_program(0)

    Manifest.write(%Manifest{splendid: entry()}, dir)

    assert %InstrumentSource{kind: :splendid, url: "/samples/splendid-grand-piano"} =
             InstrumentSource.for_program(0)
  end
end
