defmodule DrawMusic.Samples do
  @moduledoc """
  The instruments playback can use: the 128 General MIDI programs, which of
  them have samples on this server, and fetching more.

  Program 0 plays the Splendid Grand Piano; every program also has a
  MusyngKite soundfont (gleitz `midi-js-soundfonts`), named by its stem.
  """

  alias DrawMusic.Samples.{Instrument, Manifest, Splendid}

  @families [
    "Piano",
    "Chromatic Percussion",
    "Organ",
    "Guitar",
    "Bass",
    "Strings",
    "Ensemble",
    "Brass",
    "Reed",
    "Pipe",
    "Synth Lead",
    "Synth Pad",
    "Synth Effects",
    "Ethnic",
    "Percussive",
    "Sound Effects"
  ]

  # GM 1 program names, in program order.
  @names [
    "Acoustic Grand Piano",
    "Bright Acoustic Piano",
    "Electric Grand Piano",
    "Honky-tonk Piano",
    "Electric Piano 1",
    "Electric Piano 2",
    "Harpsichord",
    "Clavinet",
    "Celesta",
    "Glockenspiel",
    "Music Box",
    "Vibraphone",
    "Marimba",
    "Xylophone",
    "Tubular Bells",
    "Dulcimer",
    "Drawbar Organ",
    "Percussive Organ",
    "Rock Organ",
    "Church Organ",
    "Reed Organ",
    "Accordion",
    "Harmonica",
    "Tango Accordion",
    "Acoustic Guitar (nylon)",
    "Acoustic Guitar (steel)",
    "Electric Guitar (jazz)",
    "Electric Guitar (clean)",
    "Electric Guitar (muted)",
    "Overdriven Guitar",
    "Distortion Guitar",
    "Guitar Harmonics",
    "Acoustic Bass",
    "Electric Bass (finger)",
    "Electric Bass (pick)",
    "Fretless Bass",
    "Slap Bass 1",
    "Slap Bass 2",
    "Synth Bass 1",
    "Synth Bass 2",
    "Violin",
    "Viola",
    "Cello",
    "Contrabass",
    "Tremolo Strings",
    "Pizzicato Strings",
    "Orchestral Harp",
    "Timpani",
    "String Ensemble 1",
    "String Ensemble 2",
    "Synth Strings 1",
    "Synth Strings 2",
    "Choir Aahs",
    "Voice Oohs",
    "Synth Choir",
    "Orchestra Hit",
    "Trumpet",
    "Trombone",
    "Tuba",
    "Muted Trumpet",
    "French Horn",
    "Brass Section",
    "Synth Brass 1",
    "Synth Brass 2",
    "Soprano Sax",
    "Alto Sax",
    "Tenor Sax",
    "Baritone Sax",
    "Oboe",
    "English Horn",
    "Bassoon",
    "Clarinet",
    "Piccolo",
    "Flute",
    "Recorder",
    "Pan Flute",
    "Blown Bottle",
    "Shakuhachi",
    "Whistle",
    "Ocarina",
    "Lead 1 (square)",
    "Lead 2 (sawtooth)",
    "Lead 3 (calliope)",
    "Lead 4 (chiff)",
    "Lead 5 (charang)",
    "Lead 6 (voice)",
    "Lead 7 (fifths)",
    "Lead 8 (bass + lead)",
    "Pad 1 (new age)",
    "Pad 2 (warm)",
    "Pad 3 (polysynth)",
    "Pad 4 (choir)",
    "Pad 5 (bowed)",
    "Pad 6 (metallic)",
    "Pad 7 (halo)",
    "Pad 8 (sweep)",
    "FX 1 (rain)",
    "FX 2 (soundtrack)",
    "FX 3 (crystal)",
    "FX 4 (atmosphere)",
    "FX 5 (brightness)",
    "FX 6 (goblins)",
    "FX 7 (echoes)",
    "FX 8 (sci-fi)",
    "Sitar",
    "Banjo",
    "Shamisen",
    "Koto",
    "Kalimba",
    "Bagpipe",
    "Fiddle",
    "Shanai",
    "Tinkle Bell",
    "Agogo",
    "Steel Drums",
    "Woodblock",
    "Taiko Drum",
    "Melodic Tom",
    "Synth Drum",
    "Reverse Cymbal",
    "Guitar Fret Noise",
    "Breath Noise",
    "Seashore",
    "Bird Tweet",
    "Telephone Ring",
    "Helicopter",
    "Applause",
    "Gunshot"
  ]

  # MusyngKite file stems (gleitz `MusyngKite/names.json`), in program order.
  @stems ~w(
    acoustic_grand_piano bright_acoustic_piano electric_grand_piano honkytonk_piano
    electric_piano_1 electric_piano_2 harpsichord clavinet
    celesta glockenspiel music_box vibraphone marimba xylophone tubular_bells dulcimer
    drawbar_organ percussive_organ rock_organ church_organ reed_organ accordion harmonica
    tango_accordion
    acoustic_guitar_nylon acoustic_guitar_steel electric_guitar_jazz electric_guitar_clean
    electric_guitar_muted overdriven_guitar distortion_guitar guitar_harmonics
    acoustic_bass electric_bass_finger electric_bass_pick fretless_bass slap_bass_1 slap_bass_2
    synth_bass_1 synth_bass_2
    violin viola cello contrabass tremolo_strings pizzicato_strings orchestral_harp timpani
    string_ensemble_1 string_ensemble_2 synth_strings_1 synth_strings_2 choir_aahs voice_oohs
    synth_choir orchestra_hit
    trumpet trombone tuba muted_trumpet french_horn brass_section synth_brass_1 synth_brass_2
    soprano_sax alto_sax tenor_sax baritone_sax oboe english_horn bassoon clarinet
    piccolo flute recorder pan_flute blown_bottle shakuhachi whistle ocarina
    lead_1_square lead_2_sawtooth lead_3_calliope lead_4_chiff lead_5_charang lead_6_voice
    lead_7_fifths lead_8_bass__lead
    pad_1_new_age pad_2_warm pad_3_polysynth pad_4_choir pad_5_bowed pad_6_metallic pad_7_halo
    pad_8_sweep
    fx_1_rain fx_2_soundtrack fx_3_crystal fx_4_atmosphere fx_5_brightness fx_6_goblins
    fx_7_echoes fx_8_scifi
    sitar banjo shamisen koto kalimba bagpipe fiddle shanai
    tinkle_bell agogo steel_drums woodblock taiko_drum melodic_tom synth_drum reverse_cymbal
    guitar_fret_noise breath_noise seashore bird_tweet telephone_ring helicopter applause gunshot
  )

  @programs_per_family 8

  @instruments (for {{name, stem}, program} <- Enum.with_index(Enum.zip(@names, @stems)) do
                  %Instrument{
                    program: program,
                    name: name,
                    family: Enum.at(@families, div(program, @programs_per_family)),
                    stem: stem
                  }
                end)

  @default_stems ~w(acoustic_grand_piano electric_piano_1 harpsichord church_organ
                    acoustic_guitar_nylon violin cello flute clarinet trumpet choir_aahs marimba)

  @min_similarity 0.8
  @max_suggestions 5

  @doc "All 128 GM instruments, in program order."
  @spec instruments() :: [Instrument.t()]
  def instruments, do: @instruments

  @doc "The instrument for a GM program number."
  @spec instrument!(0..127) :: Instrument.t()
  def instrument!(program) when program in 0..127, do: Enum.at(@instruments, program)

  @doc "The 16 GM families, in GM order."
  @spec families() :: [String.t()]
  def families, do: @families

  @doc "The instruments `mix samples.fetch` downloads when given none."
  @spec default_set() :: [Instrument.t()]
  def default_set do
    Enum.map(@default_stems, fn stem -> Enum.find(@instruments, &(&1.stem == stem)) end)
  end

  @doc """
  Finds an instrument by GM name (any case), soundfont stem or program
  number. An unknown name comes back with the closest stems.
  """
  @spec lookup(String.t()) :: {:ok, Instrument.t()} | {:error, {:unknown, [String.t()]}}
  def lookup(query) do
    wanted = String.downcase(query)

    case Enum.find(@instruments, &matches?(&1, wanted)) do
      nil -> {:error, {:unknown, suggestions(wanted)}}
      instrument -> {:ok, instrument}
    end
  end

  defp matches?(%Instrument{} = instrument, wanted) do
    wanted in [
      String.downcase(instrument.name),
      instrument.stem,
      Integer.to_string(instrument.program)
    ]
  end

  defp suggestions(wanted) do
    @stems
    |> Enum.map(&{String.jaro_distance(&1, wanted), &1})
    |> Enum.filter(fn {similarity, _stem} -> similarity >= @min_similarity end)
    |> Enum.sort_by(fn {similarity, _stem} -> similarity end, :desc)
    |> Enum.take(@max_suggestions)
    |> Enum.map(fn {_similarity, stem} -> stem end)
  end

  ## Storage

  @typedoc "What can be fetched: one soundfont, or the whole Splendid Grand Piano set."
  @type item :: Instrument.t() | :splendid

  @soundfont_base "https://gleitz.github.io/midi-js-soundfonts/MusyngKite/"
  @splendid_base "https://smpldsnds.github.io/sfzinstruments-splendid-grand-piano/samples/"
  @soundfont_dir "musyngkite"
  @splendid_dir "splendid-grand-piano"
  @license_file "LICENSE.txt"
  @parallel_downloads 8

  @soundfont_license """
  Musyng Kite soundfont, converted for the web by Benjamin Gleitzman
  (https://github.com/gleitz/midi-js-soundfonts).
  Licensed under Creative Commons Attribution-ShareAlike 3.0:
  https://creativecommons.org/licenses/by-sa/3.0/
  """

  @splendid_license """
  Splendid Grand Piano: public domain samples by AKAI (a Steinway, four
  velocity layers), as converted by smpldsnds
  (https://github.com/smpldsnds/sfzinstruments-splendid-grand-piano).
  """

  @doc "Where samples are stored and served from (`config :draw_music, :samples_dir`)."
  @spec samples_dir() :: Path.t()
  def samples_dir, do: Application.fetch_env!(:draw_music, :samples_dir)

  @doc """
  Whether a program's samples are on this server. The piano counts when
  either the Splendid set or its soundfont is. Option `dir:` (default
  `samples_dir/0`).
  """
  @spec installed?(0..127, keyword()) :: boolean()
  def installed?(program, opts \\ []) do
    installed_in?(Manifest.read(dir(opts)), instrument!(program))
  end

  defp installed_in?(%Manifest{splendid: %{}}, %Instrument{program: 0}), do: true
  defp installed_in?(manifest, instrument), do: Map.has_key?(manifest.soundfonts, instrument.stem)

  @doc "The programs whose samples are on this server. Option `dir:`."
  @spec installed(keyword()) :: MapSet.t(0..127)
  def installed(opts \\ []) do
    manifest = Manifest.read(dir(opts))
    for i <- @instruments, installed_in?(manifest, i), into: MapSet.new(), do: i.program
  end

  @doc """
  An item's place inside the samples directory (and under `/samples`): a
  soundfont file, or the Splendid set's folder.
  """
  @spec relative_path(item()) :: String.t()
  def relative_path(:splendid), do: @splendid_dir
  def relative_path(%Instrument{stem: stem}), do: "#{@soundfont_dir}/#{stem}-mp3.js"

  @doc "Whether the Splendid Grand Piano set is on this server. Option `dir:`."
  @spec splendid?(keyword()) :: boolean()
  def splendid?(opts \\ []), do: match?(%Manifest{splendid: %{}}, Manifest.read(dir(opts)))

  @doc "Downloads one item; see `fetch_many/2`."
  @spec fetch(item(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def fetch(item, opts \\ []) do
    [{_item, result}] = fetch_many([item], opts)
    result
  end

  @doc """
  Downloads each item that isn't already complete, returning its size in
  bytes or why it failed, and records the ones that landed in the
  manifest. A failure leaves no partial file behind. Option `dir:`.
  """
  @spec fetch_many([item()], keyword()) :: [{item(), {:ok, non_neg_integer()} | {:error, term()}}]
  def fetch_many(items, opts \\ []) do
    dir = dir(opts)
    manifest = Manifest.read(dir)
    results = Enum.map(items, &{&1, fetch_item(&1, manifest, dir)})

    results
    |> Enum.reduce(manifest, &record/2)
    |> Manifest.write(dir)

    results
  end

  defp dir(opts), do: Keyword.get_lazy(opts, :dir, &samples_dir/0)

  defp fetch_item(%Instrument{stem: stem} = instrument, manifest, dir) do
    set_folder(dir, @soundfont_dir, @soundfont_license)
    path = Path.join(dir, relative_path(instrument))

    case complete(path, manifest.soundfonts[stem]) do
      {:ok, bytes} -> {:ok, bytes}
      :missing -> download(@soundfont_base <> Path.basename(path), path)
    end
  end

  defp fetch_item(:splendid, _manifest, dir) do
    folder = set_folder(dir, @splendid_dir, @splendid_license)

    Splendid.files()
    |> Task.async_stream(&fetch_sample(folder, &1),
      max_concurrency: @parallel_downloads,
      timeout: :infinity
    )
    |> Enum.reduce({:ok, 0}, &total/2)
  end

  # A sample file only ever appears complete: downloads land via rename.
  defp fetch_sample(folder, file) do
    path = Path.join(folder, file)

    case File.stat(path) do
      {:ok, %File.Stat{size: size}} ->
        {:ok, size}

      {:error, _missing} ->
        download(@splendid_base <> URI.encode(file, &URI.char_unreserved?/1), path)
    end
  end

  defp total({:ok, {:ok, bytes}}, {:ok, sum}), do: {:ok, sum + bytes}
  defp total({:ok, {:error, _reason} = error}, {:ok, _sum}), do: error
  defp total(_result, error), do: error

  defp complete(path, %{bytes: bytes}) do
    case File.stat(path) do
      {:ok, %File.Stat{size: ^bytes}} -> {:ok, bytes}
      _short_or_missing -> :missing
    end
  end

  defp complete(_path, nil), do: :missing

  defp set_folder(dir, name, license) do
    folder = Path.join(dir, name)
    File.mkdir_p!(folder)
    File.write!(Path.join(folder, @license_file), license)
    folder
  end

  defp download(url, path) do
    case Req.get(url, req_options()) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        tmp = path <> ".tmp"
        File.write!(tmp, body)
        File.rename!(tmp, path)
        {:ok, byte_size(body)}

      {:ok, %Req.Response{status: status}} ->
        File.rm(path)
        {:error, {:http_status, status}}

      {:error, exception} ->
        File.rm(path)
        {:error, exception}
    end
  end

  defp req_options do
    Keyword.merge([decode_body: false], Application.get_env(:draw_music, :samples_req, []))
  end

  defp record({%Instrument{stem: stem}, {:ok, bytes}}, manifest) do
    %{manifest | soundfonts: Map.put(manifest.soundfonts, stem, entry(bytes))}
  end

  defp record({:splendid, {:ok, bytes}}, manifest), do: %{manifest | splendid: entry(bytes)}
  defp record({_item, {:error, _reason}}, manifest), do: manifest

  defp entry(bytes), do: %{bytes: bytes, fetched_at: DateTime.utc_now(:second)}
end
