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

  alias DrawMusic.Music.{
    Context,
    Duration,
    Editing,
    Entry,
    KeyDetection,
    Note,
    Pitch,
    Playback,
    Score,
    TempoChange,
    Timeline
  }

  alias ExMidi.MidiFile

  @ppq Duration.ppq()
  @grid Duration.ticks(:sixty_fourth)
  @multitrack_format 1
  # A division with the top bit set counts SMPTE frames, not ticks per quarter.
  @smpte_division 0x8000
  @major_mode_byte 0
  @minor_mode_byte 1
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
  @time_denominators Context.time_denominators()
  @tempo_range Context.tempo_range()
  @defaults %Context{}
  @default_program %Version{}.instrument
  # MIDI's own default when a file sets no tempo.
  @midi_default_bpm 120
  @microseconds_per_minute 60_000_000
  @midi_clocks_per_quarter 24
  @thirty_seconds_per_quarter 8
  @note_on_velocity 80
  @note_off_velocity 64
  # Order of events at the same tick: meta events, then note-offs, then note-ons.
  @meta_rank 0
  @off_rank 1
  @on_rank 2
  @percussion_channel 9
  # Overlaps shorter than a sixteenth are legato, not a second voice.
  @legato Duration.ticks(:sixteenth)
  # The key is read from this many opening bars (or the whole piece, when
  # they hold too few notes to tell).
  @opening_bars 8
  @min_key_notes 16
  # A file's key signature when nobody set one.
  @unset_key {0, :major}
  # Tempo steps this small (a share of the tempo before), this close
  # together, all the same way, make a rit. or accel.
  @ramp_step 0.15
  @ramp_gap 2 * @ppq

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

    write({:midi_file, @multitrack_format, @ppq, tracks})
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
          value not in [nil, ""] do
        {0, @meta_rank, {:text, "#{label}: #{value}"}}
      end

    copyright =
      if composition.copyright in [nil, ""] do
        []
      else
        [{0, @meta_rank, {:copyright, composition.copyright}}]
      end

    track(
      [{0, @meta_rank, {:seq_name, composition.name}}] ++
        copyright ++
        credits ++
        tempo_events(version) ++
        [
          {0, @meta_rank,
           {:time_signature, [time_signature(version.time_num, version.time_den)]}},
          {0, @meta_rank,
           {:key_signature, [<<version.key.sf::signed-8, mode_byte(version.key.mode)>>]}},
          {0, @meta_rank,
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

  # The starting tempo, each mark, and a rit. or accel. as a step on every
  # beat (until the next change takes over), ending on its end tempo.
  defp tempo_events(version) do
    changes = Enum.sort_by((version.score || Score.new()).tempos, & &1.tick)
    next_ticks = Enum.map(tl(changes ++ [nil]), &(&1 && &1.tick))

    steps =
      changes
      |> Enum.zip(next_ticks)
      |> Enum.flat_map(fn {change, next_tick} -> tempo_steps(change, next_tick) end)

    for {tick, bpm} <- [{0, version.tempo_bpm} | steps] do
      {tick, @meta_rank, {:tempo, [round(@microseconds_per_minute / bpm)]}}
    end
  end

  defp tempo_steps(%TempoChange{to_tick: nil} = change, _next_tick),
    do: [{change.tick, change.bpm}]

  defp tempo_steps(%TempoChange{} = change, next_tick) do
    stop = min(change.to_tick, next_tick || change.to_tick)
    span = change.to_tick - change.tick

    beats =
      for tick <- change.tick..(stop - 1)//@ppq do
        {tick, change.bpm + (change.to_bpm - change.bpm) * (tick - change.tick) / span}
      end

    if stop == change.to_tick, do: beats ++ [{stop, change.to_bpm}], else: beats
  end

  defp staff_track(name, channel, instrument, sounds) do
    notes =
      Enum.flat_map(sounds, fn sound ->
        [
          {sound.start, @on_rank, {:on, [channel, sound.midi, @note_on_velocity]}},
          {sound.start + sound.ticks, @off_rank,
           {:off, [channel, sound.midi, @note_off_velocity]}}
        ]
      end)

    track([
      {0, @meta_rank, {:seq_name, name}},
      {0, @meta_rank, {:program, [channel, instrument]}} | notes
    ])
  end

  # Absolute `{tick, rank, {name, values}}` events into a delta-time track.
  defp track(events) do
    {deltas, _last_tick} =
      events
      |> Enum.sort_by(fn {tick, rank, _event} -> {tick, rank} end)
      |> Enum.map_reduce(0, fn {tick, _rank, {name, values}}, previous ->
        {{name, tick - previous, values}, tick}
      end)

    {:track, deltas ++ [{:track_end, 0, []}]}
  end

  # The metronome clicks once per felt beat.
  defp time_signature(num, den) do
    beat = Context.beam_group_ticks(%Context{time_num: num, time_den: den})
    clocks_per_click = max(div(beat * @midi_clocks_per_quarter, @ppq), 1)
    <<num, log2(den), clocks_per_click, @thirty_seconds_per_quarter>>
  end

  defp log2(1), do: 0
  defp log2(n), do: 1 + log2(div(n, 2))

  defp mode_byte(:minor), do: @minor_mode_byte
  defp mode_byte(:major), do: @major_mode_byte

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
      {:midi_file, _format, division, tracks} when division < @smpte_division ->
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
    trimmed =
      bytes
      |> IO.iodata_to_binary()
      |> String.trim()

    case trimmed do
      "" -> nil
      text -> text
    end
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
    {num, den} = time_signature_of(all)

    staves =
      tracks
      |> Enum.map(&played_notes(&1, division))
      |> assign_staves()

    {sf, mode} = start_key(key_signature(all), staves, %Context{time_num: num, time_den: den})
    {tempo_bpm, tempos} = tempos(all, division)

    ctx = %Context{
      sf: sf,
      mode: mode,
      time_num: num,
      time_den: den,
      tempo_bpm: tempo_bpm
    }

    entries = Enum.flat_map(staves, fn {staff, notes} -> voiced_entries(notes, staff, sf) end)

    with {:ok, score} <- Timeline.rebar(%{Score.new() | tempos: tempos}, ctx, entries) do
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

  # The file's key signature, or nil when it sets none.
  defp key_signature(events) do
    Enum.find_value(events, fn
      {_tick, :key_signature, [<<sf::signed-8, mi>>]} when sf in -7..7 ->
        {sf, if(mi == @minor_mode_byte, do: :minor, else: :major)}

      _event ->
        nil
    end)
  end

  # The key the music starts in, from its opening bars. The file's own key
  # often isn't set (C major is the usual leftover), so the notes decide;
  # where the file names another key with the same signature, its major or
  # minor is kept (the notes alone can mistake a key for its relative).
  defp start_key(file_key, staves, ctx) do
    opening_end = @opening_bars * Context.measure_ticks(ctx)
    notes = for {_staff, notes} <- staves, {key, start, ticks} <- notes, do: {key, start, ticks}
    opening = Enum.filter(notes, fn {_key, start, _ticks} -> start < opening_end end)
    sample = if length(opening) < @min_key_notes, do: notes, else: opening
    detected = KeyDetection.detect(Enum.map(sample, fn {key, _start, ticks} -> {key, ticks} end))

    case {file_key, detected} do
      {file_key, nil} -> file_key || {@defaults.sf, @defaults.mode}
      {{sf, _mode} = file_key, {sf, _detected_mode}} when file_key != @unset_key -> file_key
      {_file_key, detected} -> detected
    end
  end

  defp time_signature_of(events) do
    Enum.find_value(events, {@defaults.time_num, @defaults.time_den}, fn
      {_tick, :time_signature, [<<num, dd, _rest::binary>>]} ->
        den = 1 <<< dd
        if num in 1..Context.max_time_num() and den in @time_denominators, do: {num, den}

      _event ->
        nil
    end)
  end

  # The starting tempo and the changes after it. A change to the tempo
  # already in force is dropped. A run of small steps the same way (each at
  # most @ramp_step of the last, at most @ramp_gap apart) is a rit. or
  # accel. from the run's first tempo to its last; any other change is a
  # mark.
  defp tempos(events, division) do
    changes =
      events
      |> Enum.flat_map(fn
        {tick, :tempo, [mpq]} when mpq > 0 -> [{quantize(tick, division), bpm(mpq)}]
        _event -> []
      end)
      |> Enum.sort_by(&elem(&1, 0))
      # Several at one tick: the last one counts.
      |> Enum.reverse()
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.reverse()

    {start, later} =
      case changes do
        [{0, bpm} | later] -> {bpm, later}
        later -> {@midi_default_bpm, later}
      end

    {kept, _bpm} =
      Enum.flat_map_reduce(later, start, fn
        {_tick, bpm}, bpm -> {[], bpm}
        {_tick, bpm} = change, _previous -> {[change], bpm}
      end)

    {start, group_ramps(kept)}
  end

  defp bpm(microseconds_per_quarter) do
    (@microseconds_per_minute / microseconds_per_quarter)
    |> round()
    |> max(@tempo_range.first)
    |> min(@tempo_range.last)
  end

  defp group_ramps([]), do: []

  defp group_ramps([first | rest] = changes) do
    case ramp_run(changes) do
      [_one, _two, _three | _more] = run ->
        {last_tick, last_bpm} = List.last(run)
        {tick, bpm} = first

        [
          %TempoChange{
            id: Ecto.UUID.generate(),
            tick: tick,
            bpm: bpm,
            to_tick: last_tick,
            to_bpm: last_bpm
          }
          | group_ramps(Enum.drop(changes, length(run)))
        ]

      _short ->
        {tick, bpm} = first
        [%TempoChange{id: Ecto.UUID.generate(), tick: tick, bpm: bpm} | group_ramps(rest)]
    end
  end

  # The longest run from the first change whose steps all go one way.
  defp ramp_run([first | rest]) do
    {run, _direction} =
      Enum.reduce_while(rest, {[first], nil}, fn {tick, bpm} = change,
                                                 {[{last_tick, last_bpm} | _] = run, direction} ->
        step = bpm - last_bpm
        way = if step > 0, do: :up, else: :down

        if direction in [way, nil] and abs(step) <= last_bpm * @ramp_step and
             tick - last_tick <= @ramp_gap do
          {:cont, {[change | run], way}}
        else
          {:halt, {run, direction}}
        end
      end)

    Enum.reverse(run)
  end

  defp program(events) do
    Enum.find_value(events, @default_program, fn
      {_tick, :program, [channel, program]} when channel != @percussion_channel -> program
      _event -> nil
    end)
  end

  # [{midi, start, ticks}] in our ticks, from note on/off pairs.
  defp played_notes(events, division) do
    last_tick =
      events
      |> Enum.map(&elem(&1, 0))
      |> Enum.max(fn -> 0 end)

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

  # One list of notes per staff, so a staff's voices are shared out among
  # all the tracks that land on it.
  defp assign_staves(per_track) do
    case Enum.reject(per_track, &(&1 == [])) do
      [treble, bass | others] ->
        [{:treble, more_treble}, {:bass, more_bass}] = split_at_middle_c(Enum.concat(others))
        [{:treble, treble ++ more_treble}, {:bass, bass ++ more_bass}]

      [only] ->
        split_at_middle_c(only)

      [] ->
        []
    end
  end

  defp split_at_middle_c(notes) do
    {treble, bass} =
      Enum.split_with(notes, fn {key, _start, _ticks} -> key >= Pitch.middle_c() end)

    [{:treble, treble}, {:bass, bass}]
  end

  # Notes struck together with the same length form a chord. Chords go in
  # the lowest voice free when they start, higher chords first at a shared
  # onset; one that finds all four voices busy is dropped.
  defp voiced_entries(notes, staff, sf) do
    onsets =
      notes
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Enum.sort()

    next_onset = Map.new(Enum.zip(onsets, tl(onsets ++ [nil])))

    notes
    |> Enum.map(fn {key, start, ticks} ->
      {key, start, trim_legato(start, ticks, next_onset[start])}
    end)
    |> Enum.group_by(fn {_key, start, ticks} -> {start, ticks} end, &elem(&1, 0))
    |> Enum.sort_by(fn {{start, _ticks}, keys} -> {start, -Enum.max(keys)} end)
    |> Enum.flat_map_reduce(Map.new(Note.voices(), &{&1, 0}), fn {{start, ticks}, keys}, free ->
      case Enum.find(Note.voices(), &(free[&1] <= start)) do
        nil ->
          {[], free}

        voice ->
          {chord(keys, staff, voice, start, ticks, sf), Map.put(free, voice, start + ticks)}
      end
    end)
    |> elem(0)
  end

  defp trim_legato(start, ticks, next)
       when is_integer(next) and start + ticks > next and start + ticks - next < @legato do
    next - start
  end

  defp trim_legato(_start, ticks, _next), do: ticks

  # Repeated letters in a chord keep the first.
  defp chord(keys, staff, voice, start, ticks, sf) do
    spellings =
      keys
      |> Enum.map(&Pitch.spell(&1, sf))
      |> Enum.uniq_by(&elem(&1, 0))

    for {step, alter} <- spellings do
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
