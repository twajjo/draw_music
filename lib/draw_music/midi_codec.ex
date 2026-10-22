defmodule DrawMusic.MidiCodec do
  @moduledoc """
  Converts versions to and from Standard MIDI Files. File encoding and
  decoding is done by `ExMidi.MidiFile`; this module maps between our
  scores and MIDI events.

  Export writes Format 1 at 960 ticks per quarter: a conductor track (name,
  credits, tempo, time and key signature) and one track per staff (treble
  on channel 1, bass on channel 2). The conductor track also carries the
  complete version as JSON in a sequencer-specific event (manufacturer id
  0x7D, reserved for non-commercial use), so files made here re-import
  exactly.

  Import uses that JSON when present. Otherwise it converts the notes:
  times are rounded to the nearest 64th; the first two tracks with notes
  become treble and bass (or notes split at middle C when there is only
  one); notes struck together with the same length become a chord, placed
  in the lowest of the staff's four voices that is free at that moment, so
  a held note under moving ones keeps its length. Overlaps of less than a
  sixteenth are legato playing and are trimmed. A chord that finds all four
  voices busy is dropped. Gaps become rests. Percussion (channel 10) is
  ignored.
  """

  import Bitwise, only: [<<<: 2]

  alias DrawMusic.Library.{Composition, Import, Key, Version}
  alias DrawMusic.Music.{Context, Editing, Entry, Note, Pitch, Playback, Score, Timeline}
  alias ExMidi.MidiFile

  @ppq 960
  @grid 60
  @signature <<0x7D, "DRAWMUSIC", 1>>
  @credit_fields [:subtitle, :composer, :arranger, :lyricist, :copyright, :notes]
  @version_fields [
    :label,
    :time_num,
    :time_den,
    :time_symbol,
    :tempo_bpm,
    :tempo_text,
    :pickup_ticks,
    :instrument,
    :score
  ]
  @time_denominators [1, 2, 4, 8, 16, 32, 64]
  @percussion_channel 9
  # Overlaps shorter than a sixteenth are legato, not a second voice.
  @legato 240

  ## Export

  @doc "Encodes a version (with key and composition loaded) as a .mid binary."
  @spec export(Version.t()) :: {:ok, binary()} | {:error, term()}
  def export(%Version{key: %Key{composition: %Composition{} = composition}} = version) do
    score = version.score || Score.new()
    ctx = Context.from_version(version)
    sounds = Playback.sounds(score, ctx)

    tracks = [
      conductor_track(composition, version),
      staff_track("Treble", 0, version.instrument, Enum.filter(sounds, &(&1.staff == :treble))),
      staff_track("Bass", 1, version.instrument, Enum.filter(sounds, &(&1.staff == :bass)))
    ]

    write({:midi_file, 1, @ppq, tracks})
  end

  defp conductor_track(composition, version) do
    credits =
      for {field, label} <- [
            subtitle: "Subtitle",
            composer: "Composer",
            arranger: "Arranger",
            lyricist: "Lyricist"
          ],
          value = Map.fetch!(composition, field),
          value not in [nil, ""],
          do: {0, 0, {:text, "#{label}: #{value}"}}

    copyright =
      if composition.copyright in [nil, ""],
        do: [],
        else: [{0, 0, {:copyright, composition.copyright}}]

    track(
      [{0, 0, {:seq_name, composition.name}}] ++
        copyright ++
        credits ++
        [
          {0, 0, {:tempo, [round(60_000_000 / version.tempo_bpm)]}},
          {0, 0, {:time_signature, [time_signature(version.time_num, version.time_den)]}},
          {0, 0, {:key_signature, [<<version.key.sf::signed-8, mode_byte(version.key.mode)>>]}},
          {0, 0,
           {:sequencer_specific, [@signature <> JSON.encode!(payload(composition, version))]}}
        ]
    )
  end

  defp payload(composition, version) do
    %Import{
      name: composition.name,
      composition: Map.take(composition, @credit_fields),
      key: %{sf: version.key.sf, mode: version.key.mode},
      version:
        version
        |> Map.take(@version_fields -- [:score])
        |> Map.put(:score, Ecto.embedded_dump(version.score || Score.new(), :json))
    }
  end

  defp staff_track(name, channel, instrument, sounds) do
    notes =
      Enum.flat_map(sounds, fn sound ->
        [
          {sound.start, 2, {:on, [channel, sound.midi, 80]}},
          {sound.start + sound.ticks, 1, {:off, [channel, sound.midi, 64]}}
        ]
      end)

    track([{0, 0, {:seq_name, name}}, {0, 0, {:program, [channel, instrument]}} | notes])
  end

  # Absolute `{tick, rank, {name, values}}` events into a delta-time track.
  # At equal ticks, rank orders meta events, then note-offs, then note-ons.
  defp track(events) do
    {deltas, _last_tick} =
      events
      |> Enum.sort_by(fn {tick, rank, _event} -> {tick, rank} end)
      |> Enum.map_reduce(0, fn {tick, _rank, {name, values}}, previous ->
        {{name, tick - previous, values}, tick}
      end)

    {:track, deltas ++ [{:track_end, 0, []}]}
  end

  defp time_signature(num, den) do
    clocks_per_click = div(if(num > 3 and rem(num, 3) == 0, do: 3, else: 1) * 96, den)
    <<num, log2(den), max(clocks_per_click, 1), 8>>
  end

  defp log2(1), do: 0
  defp log2(n), do: 1 + log2(div(n, 2))

  defp mode_byte(:minor), do: 1
  defp mode_byte(_major), do: 0

  defp write(file) do
    path = Path.join(System.tmp_dir!(), "draw_music_#{Ecto.UUID.generate()}.mid")

    try do
      with :ok <- MidiFile.write(file, path), do: File.read(path)
    after
      File.rm(path)
    end
  end

  ## Import

  @doc """
  Reads a .mid file into a `DrawMusic.Library.Import` for
  `DrawMusic.Library.import_score/4`. The name comes from the first track
  name, else `filename` without its extension.
  """
  @spec import(Path.t(), String.t()) ::
          {:ok, Import.t()}
          | {:error, :invalid_midi | :smpte_unsupported | :unrepresentable | :before_start}
  def import(path, filename) do
    case MidiFile.read(path) do
      {:midi_file, _format, division, tracks} when division < 0x8000 ->
        tracks = Enum.map(tracks, &absolute/1)
        name = track_name(tracks) || Path.rootname(Path.basename(filename))

        case embedded_payload(tracks) do
          {:ok, payload} -> {:ok, from_payload(payload, name)}
          :none -> convert(tracks, division, name)
        end

      {:midi_file, _format, _division, _tracks} ->
        {:error, :smpte_unsupported}

      {:error, _reason} ->
        {:error, :invalid_midi}
    end
  end

  defp absolute({:track, events}) do
    {events, _tick} =
      Enum.map_reduce(events, 0, fn {name, delta, values}, tick ->
        {{tick + delta, name, values}, tick + delta}
      end)

    events
  end

  defp track_name(tracks) do
    Enum.find_value(tracks, fn events ->
      Enum.find_value(events, fn
        {_tick, :seq_name, bytes} -> text(bytes)
        _event -> nil
      end)
    end)
  end

  defp text(bytes) do
    bytes |> IO.iodata_to_binary() |> String.trim() |> then(&if(&1 == "", do: nil, else: &1))
  end

  defp embedded_payload(tracks) do
    Enum.find_value(tracks, :none, fn events ->
      Enum.find_value(events, fn
        {_tick, :sequencer_specific, [@signature <> json]} -> decode_payload(json)
        _event -> nil
      end)
    end)
  end

  defp decode_payload(json) do
    case JSON.decode(json) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      _invalid -> nil
    end
  end

  defp from_payload(payload, name) do
    %Import{
      name: name,
      composition: known(payload["composition"], @credit_fields),
      key: known(payload["key"], [:sf, :mode]),
      version: known(payload["version"], @version_fields)
    }
  end

  # String-keyed map -> atom-keyed map with only the expected fields.
  defp known(map, fields) when is_map(map) do
    for field <- fields, Map.has_key?(map, Atom.to_string(field)), into: %{} do
      {field, map[Atom.to_string(field)]}
    end
  end

  defp known(_not_a_map, _fields), do: %{}

  defp convert(tracks, division, name) do
    all = Enum.concat(tracks)
    {sf, mode} = key_signature(all)
    {num, den} = time_signature_of(all)

    ctx = %Context{
      sf: sf,
      mode: mode,
      time_num: num,
      time_den: den,
      tempo_bpm: tempo(all)
    }

    entries =
      tracks
      |> Enum.map(&played_notes(&1, division))
      |> assign_staves()
      |> Enum.flat_map(fn {staff, notes} -> voiced_entries(notes, staff, sf) end)

    with {:ok, score} <- Timeline.rebar(Score.new(), ctx, entries) do
      {:ok,
       %Import{
         name: name,
         composition: %{},
         key: %{sf: sf, mode: mode},
         version: %{
           time_num: num,
           time_den: den,
           tempo_bpm: ctx.tempo_bpm,
           instrument: program(all),
           score: Editing.fill_rests(score, ctx)
         }
       }}
    end
  end

  defp key_signature(events) do
    Enum.find_value(events, {0, :major}, fn
      {_tick, :key_signature, [<<sf::signed-8, mi>>]} when sf in -7..7 ->
        {sf, if(mi == 1, do: :minor, else: :major)}

      _event ->
        nil
    end)
  end

  defp time_signature_of(events) do
    Enum.find_value(events, {4, 4}, fn
      {_tick, :time_signature, [<<num, dd, _rest::binary>>]} ->
        den = 1 <<< dd
        if num in 1..32 and den in @time_denominators, do: {num, den}

      _event ->
        nil
    end)
  end

  defp tempo(events) do
    Enum.find_value(events, 120, fn
      {_tick, :tempo, [mpq]} when mpq > 0 -> round(60_000_000 / mpq) |> max(20) |> min(400)
      _event -> nil
    end)
  end

  defp program(events) do
    Enum.find_value(events, 0, fn
      {_tick, :program, [channel, program]} when channel != @percussion_channel -> program
      _event -> nil
    end)
  end

  # [{midi, start, ticks}] on our 960-tick grid, from note on/off pairs.
  defp played_notes(events, division) do
    last_tick = events |> Enum.map(&elem(&1, 0)) |> Enum.max(fn -> 0 end)

    {notes, open} =
      Enum.reduce(events, {[], %{}}, fn
        {_t, _name, [@percussion_channel | _]}, acc ->
          acc

        {tick, :on, [channel, key, _vel]}, {notes, open} ->
          {notes, Map.update(open, {channel, key}, [tick], &(&1 ++ [tick]))}

        {tick, :off, [channel, key, _vel]}, {notes, open} ->
          case Map.get(open, {channel, key}, []) do
            [] -> {notes, open}
            [start | rest] -> {[{key, start, tick} | notes], Map.put(open, {channel, key}, rest)}
          end

        _event, acc ->
          acc
      end)

    dangling = for {{_channel, key}, starts} <- open, start <- starts, do: {key, start, last_tick}

    for {key, on, off} <- notes ++ dangling, Pitch.in_range?(key) do
      start = quantize(on, division)
      {key, start, max(quantize(off, division) - start, @grid)}
    end
  end

  defp quantize(tick, division), do: round(tick * @ppq / division / @grid) * @grid

  defp assign_staves(per_track) do
    case Enum.reject(per_track, &(&1 == [])) do
      [treble, bass | others] ->
        [{:treble, treble}, {:bass, bass}] ++ split_at_middle_c(Enum.concat(others))

      [only] ->
        split_at_middle_c(only)

      [] ->
        []
    end
  end

  defp split_at_middle_c(notes) do
    {treble, bass} = Enum.split_with(notes, fn {key, _start, _ticks} -> key >= 60 end)
    [{:treble, treble}, {:bass, bass}]
  end

  # Notes struck together with the same length form a chord. Chords go in
  # the lowest voice free when they start, higher chords first at a shared
  # onset; one that finds all four voices busy is dropped.
  defp voiced_entries(notes, staff, sf) do
    onsets = notes |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()
    next_onset = Map.new(Enum.zip(onsets, tl(onsets ++ [nil])))

    notes
    |> Enum.map(fn {key, start, ticks} ->
      {key, start, trim_legato(start, ticks, next_onset[start])}
    end)
    |> Enum.group_by(fn {_key, start, ticks} -> {start, ticks} end, &elem(&1, 0))
    |> Enum.sort_by(fn {{start, _ticks}, keys} -> {start, -Enum.max(keys)} end)
    |> Enum.flat_map_reduce(Map.new(1..4, &{&1, 0}), fn {{start, ticks}, keys}, free ->
      case Enum.find(1..4, &(free[&1] <= start)) do
        nil ->
          {[], free}

        voice ->
          {chord(keys, staff, voice, start, ticks, sf), Map.put(free, voice, start + ticks)}
      end
    end)
    |> elem(0)
  end

  defp trim_legato(start, ticks, next)
       when is_integer(next) and start + ticks > next and start + ticks - next < @legato,
       do: next - start

  defp trim_legato(_start, ticks, _next), do: ticks

  # Repeated letters in a chord keep the first.
  defp chord(keys, staff, voice, start, ticks, sf) do
    for {step, alter} <- keys |> Enum.map(&Pitch.spell(&1, sf)) |> Enum.uniq_by(&elem(&1, 0)) do
      note = %Note{
        id: Ecto.UUID.generate(),
        staff: staff,
        voice: voice,
        offset: 0,
        value: nil,
        dots: 0,
        step: step,
        alter: alter
      }

      %Entry{kind: :note, start: start, ticks: ticks, event: note}
    end
  end
end
