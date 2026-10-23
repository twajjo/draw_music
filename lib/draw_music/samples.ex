defmodule DrawMusic.Samples do
  @moduledoc """
  The instruments playback can use: the 128 General MIDI programs, which of
  them have samples on this server, and fetching more.

  Program 0 plays the Splendid Grand Piano; every program also has a
  MusyngKite soundfont (gleitz `midi-js-soundfonts`), named by its stem.
  """

  alias DrawMusic.Samples.Instrument

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
end
