defmodule DrawMusic.Engraving.Notes do
  @moduledoc """
  Lays out one measure's notes and rests as drawing items
  (`DrawMusic.Engraving.Item`): noteheads, ledger lines, accidentals, dots,
  stems, flags, beams and rests.

  Chords are the notes of one voice that share an offset. In a chord, a
  note a second away from its neighbour moves to the other side of the
  stem. Accidentals stagger leftwards in columns when they would collide.
  """

  alias DrawMusic.Engraving.{
    Anchor,
    Beam,
    ChordLayout,
    Glyph,
    Head,
    Item,
    Line,
    MeasureGeometry,
    Smufl,
    Staff
  }

  alias DrawMusic.Music.{
    Accidentals,
    BeamGroup,
    Beaming,
    Context,
    Duration,
    Gaps,
    Measure,
    Stems
  }

  @half_space 0.5
  @stem_length 3.5
  # Stems of values with more flags than this grow a beam step per flag.
  @flags_on_plain_stem 2
  @min_beamed_stem 2.5
  @max_beam_rise 1.0
  # Distance between beam levels: beam thickness plus beam spacing.
  @beam_step 0.75
  @beam_stub 1.0
  # Guards the slope of a beam whose first and last stems coincide.
  @min_beam_run 1.0e-6
  @dot_gap 0.3
  @dot_step 0.5
  @accidental_gap 0.25
  @accidental_column 1.2
  # Accidentals closer than this many steps go in different columns.
  @accidental_clearance 6
  @voice_rest_shift 2
  # A whole rest hangs from the staff's second line.
  @whole_rest_line 1

  @rest_glyphs %{
    whole: :restWhole,
    half: :restHalf,
    quarter: :restQuarter,
    eighth: :rest8th,
    sixteenth: :rest16th,
    thirty_second: :rest32nd,
    sixty_fourth: :rest64th,
    hundred_twenty_eighth: :rest128th,
    two_hundred_fifty_sixth: :rest256th
  }

  @flag_glyphs %{
    {1, :up} => :flag8thUp,
    {1, :down} => :flag8thDown,
    {2, :up} => :flag16thUp,
    {2, :down} => :flag16thDown,
    {3, :up} => :flag32ndUp,
    {3, :down} => :flag32ndDown,
    {4, :up} => :flag64thUp,
    {4, :down} => :flag64thDown,
    {5, :up} => :flag128thUp,
    {5, :down} => :flag128thDown,
    {6, :up} => :flag256thUp,
    {6, :down} => :flag256thDown
  }

  @accidental_glyphs %{
    -2 => :accidentalDoubleFlat,
    -1 => :accidentalFlat,
    0 => :accidentalNatural,
    1 => :accidentalSharp,
    2 => :accidentalDoubleSharp
  }

  @doc """
  Items for `measure` (number `index`) laid out in `geom` (see
  `DrawMusic.Engraving.MeasureGeometry.x_at/2` for where offsets go). `tied_in`
  holds the ids of notes continuing a tie from the previous measure.

  Returns `{items, anchors}`; `anchors` maps each note id to its
  `DrawMusic.Engraving.Anchor`, for ties.
  """
  @spec items(Measure.t(), non_neg_integer(), MeasureGeometry.t(), Context.t(), MapSet.t()) ::
          {[Item.t()], %{Ecto.UUID.t() => Anchor.t()}}
  def items(%Measure{} = measure, index, %MeasureGeometry{} = geom, %Context{} = ctx, tied_in) do
    voice_counts = voice_counts(measure)
    chords = Enum.group_by(measure.notes, &{&1.staff, &1.voice, &1.offset})
    groups = Beaming.groups(measure, ctx, index)

    group_of =
      for g <- groups, offset <- g.offsets, into: %{} do
        {{g.staff, g.voice, offset}, g}
      end

    accidentals = Accidentals.displayed(measure, ctx.sf, tied_in)

    laid =
      Map.new(chords, fn {{staff, voice, _offset} = key, notes} ->
        steps = stem_steps(notes, group_of[key], chords)
        dir = Stems.direction(staff, steps, voice, voice_counts[staff])
        {key, chord(notes, key, dir, geom, accidentals)}
      end)

    stems =
      for {key, chord} <- laid, not Map.has_key?(group_of, key), item <- free_stem(chord) do
        item
      end

    items =
      Enum.flat_map(laid, fn {_key, chord} -> chord.items end) ++
        stems ++ Enum.flat_map(groups, &beam(&1, laid)) ++ rests(measure, geom, voice_counts)

    anchors = for {_key, chord} <- laid, anchor <- chord.anchors, into: %{}, do: anchor
    {items, anchors}
  end

  # A beamed chord's stem direction is decided by its whole beam group.
  defp stem_steps(notes, nil, _chords), do: Enum.map(notes, & &1.step)

  defp stem_steps(_notes, group, chords) do
    for o <- group.offsets, n <- chords[{group.staff, group.voice, o}], do: n.step
  end

  defp voice_counts(measure) do
    (measure.notes ++ measure.rests)
    |> Enum.group_by(& &1.staff, & &1.voice)
    |> Map.new(fn {staff, voices} -> {staff, length(Enum.uniq(voices))} end)
  end

  ## Chords

  defp chord([first | _] = notes, {staff, _voice, offset}, dir, geom, accidentals) do
    glyph = notehead(first.value)
    width = Smufl.width(glyph)
    x = MeasureGeometry.x_at(geom, offset)
    heads = heads(notes, staff, dir, x, width)

    {left, rightmost} =
      heads
      |> Enum.map(& &1.x)
      |> Enum.min_max()

    right = rightmost + width
    {top_y, bottom_y} = Enum.min_max(Enum.map(heads, & &1.y))

    %ChordLayout{
      staff: staff,
      dir: dir,
      value: first.value,
      glyph: glyph,
      x: x,
      top_y: top_y,
      bottom_y: bottom_y,
      items:
        Enum.map(heads, &%{glyph(:notehead, glyph, &1.x, &1.y, &1.note.id) | staff: staff}) ++
          ledgers(heads, staff, left, right) ++
          dots(heads, right) ++ accidentals(heads, left, accidentals),
      anchors:
        for(h <- heads, do: {h.note.id, %Anchor{x0: h.x, x1: h.x + width, y: h.y, dir: dir}})
    }
  end

  defp notehead(:whole), do: :noteheadWhole
  defp notehead(:half), do: :noteheadHalf
  defp notehead(_value), do: :noteheadBlack

  # Walking from the stem's base, a note a second above (stem up) or below
  # (stem down) an unmoved note moves across the stem.
  defp heads(notes, staff, dir, x, width) do
    notes
    |> Enum.sort_by(& &1.step, from_stem_base(dir))
    |> Enum.map_reduce(nil, fn note, previous ->
      moved = second_from_unmoved?(note, previous)

      head = %Head{
        note: note,
        x: x + shift(moved, dir, width),
        y: Staff.y(staff, note.step),
        moved: moved
      }

      {head, head}
    end)
    |> elem(0)
  end

  defp from_stem_base(:up), do: :asc
  defp from_stem_base(:down), do: :desc

  defp second_from_unmoved?(_note, nil), do: false
  defp second_from_unmoved?(_note, %Head{moved: true}), do: false
  defp second_from_unmoved?(note, %Head{note: previous}), do: abs(note.step - previous.step) == 1

  defp shift(false, _dir, _width), do: 0
  defp shift(true, :up, width), do: width
  defp shift(true, :down, width), do: -width

  defp ledgers(heads, staff, left, right) do
    extension = Smufl.default("legerLineExtension")
    thickness = Smufl.default("legerLineThickness")

    heads
    |> Enum.flat_map(&Staff.ledger_steps(staff, &1.note.step))
    |> Enum.uniq()
    |> Enum.map(fn step ->
      y = Staff.y(staff, step)
      line(:ledger, left - extension, y, right + extension, y, thickness)
    end)
  end

  # Dots sit in a space: a note on a line puts its dot in the space above.
  defp dots(heads, right) do
    for head <- heads, i <- 0..(head.note.dots - 1)//1 do
      y = dot_y(head.y, Staff.line?(head.note.step))
      glyph(:dot, :augmentationDot, right + @dot_gap + i * @dot_step, y)
    end
  end

  defp dot_y(y, true = _on_line?), do: y - @half_space
  defp dot_y(y, false), do: y

  # Top to bottom, each accidental goes in the first column whose last sign
  # is far enough above it.
  defp accidentals(heads, left, shown) do
    heads
    |> Enum.filter(&Map.has_key?(shown, &1.note.id))
    |> Enum.sort_by(& &1.note.step, :desc)
    |> Enum.map_reduce([], fn head, columns ->
      glyph = Map.fetch!(@accidental_glyphs, shown[head.note.id])
      {column, columns} = accidental_column(columns, head.note.step)
      right = left - @accidental_gap - column * @accidental_column
      {glyph(:accidental, glyph, right - Smufl.width(glyph), head.y), columns}
    end)
    |> elem(0)
  end

  # `columns` holds the lowest step written in each column so far.
  defp accidental_column(columns, step) do
    case Enum.find_index(columns, &(&1 - step >= @accidental_clearance)) do
      nil -> {length(columns), columns ++ [step]}
      column -> {column, List.replace_at(columns, column, step)}
    end
  end

  ## Stems, flags and beams

  defp free_stem(%ChordLayout{value: :whole}), do: []

  defp free_stem(chord) do
    flags = Duration.flags(chord.value)
    length = @stem_length + max(flags - @flags_on_plain_stem, 0) * @beam_step
    {x, base} = stem_attachment(chord)

    tip =
      case chord.dir do
        :up -> min(chord.top_y - length, Staff.middle(chord.staff))
        :down -> max(chord.bottom_y + length, Staff.middle(chord.staff))
      end

    [stem(x, base, tip, chord.dir) | flag(flags, chord.dir, x, tip)]
  end

  # Stem centre x and the y where it meets the notehead, from the
  # notehead's SMuFL stem anchors.
  defp stem_attachment(chord) do
    half = Smufl.default("stemThickness") / 2

    case chord.dir do
      :up ->
        {ax, ay} = Smufl.anchor(chord.glyph, "stemUpSE")
        {chord.x + ax - half, chord.bottom_y - ay}

      :down ->
        {ax, ay} = Smufl.anchor(chord.glyph, "stemDownNW")
        {chord.x + ax + half, chord.top_y - ay}
    end
  end

  defp stem(x, base, tip, dir) do
    %{line(:stem, x, base, x, tip, Smufl.default("stemThickness")) | dir: dir}
  end

  defp flag(0, _dir, _x, _tip), do: []

  defp flag(flags, dir, x, tip) do
    glyph = Map.fetch!(@flag_glyphs, {flags, dir})
    [glyph(:flag, glyph, x - Smufl.default("stemThickness") / 2, tip)]
  end

  # The beam runs between the ideal stem tips of the first and last chords,
  # its slope clamped, then moves away from the notes until every stem is
  # long enough.
  defp beam(%BeamGroup{staff: staff, voice: voice, offsets: offsets}, laid) do
    chords = Enum.map(offsets, &Map.fetch!(laid, {staff, voice, &1}))
    dir = hd(chords).dir
    sign = away(dir)
    attachments = Enum.map(chords, &stem_attachment/1)
    extremes = Enum.map(chords, &tip_side(&1, dir))
    levels = Enum.map(chords, &Duration.flags(&1.value))

    {x1, _} = hd(attachments)
    {xn, _} = List.last(attachments)
    y1 = hd(extremes) + sign * @stem_length

    rise =
      (List.last(extremes) + sign * @stem_length - y1)
      |> max(-@max_beam_rise)
      |> min(@max_beam_rise)

    sloped = fn x -> y1 + rise * (x - x1) / max(xn - x1, @min_beam_run) end

    min_length = @min_beamed_stem + (Enum.max(levels) - 1) * @beam_step

    shift =
      attachments
      |> Enum.zip(extremes)
      |> Enum.map(fn {{x, _base}, extreme} ->
        (sloped.(x) - (extreme + sign * min_length)) * -sign
      end)
      |> Enum.max()
      |> max(0)

    beam_y = fn x -> sloped.(x) + sign * shift end
    half = Smufl.default("stemThickness") / 2
    xs = Enum.map(attachments, &elem(&1, 0))

    stems = for {x, base} <- attachments, do: stem(x, base, beam_y.(x), dir)

    beams =
      for level <- 1..Enum.max(levels), {xa, xb} <- level_spans(xs, levels, level, half) do
        beam_item(xa, xb, beam_y, level, sign)
      end

    stems ++ beams
  end

  # y grows downward: stems up point toward negative y.
  defp away(:up), do: -1
  defp away(:down), do: 1

  defp tip_side(chord, :up), do: chord.top_y
  defp tip_side(chord, :down), do: chord.bottom_y

  # Spans of beam `level`: over each run of chords with at least that many
  # flags, or a short stub for a lone chord, pointing into the group.
  defp level_spans(xs, levels, level, half) do
    last = length(xs) - 1

    levels
    |> Enum.with_index()
    |> Enum.chunk_by(fn {flags, _i} -> flags >= level end)
    |> Enum.filter(fn [{flags, _i} | _] -> flags >= level end)
    |> Enum.map(fn
      [{_flags, i}] ->
        stub(xs, i, last, half)

      [{_flags, i} | _] = run ->
        {_flags, j} = List.last(run)
        {Enum.at(xs, i) - half, Enum.at(xs, j) + half}
    end)
  end

  # A lone chord's stub points back from the last stem, forward otherwise.
  defp stub(xs, last, last, half) do
    x = Enum.at(xs, last)
    length = stub_length(x, Enum.at(xs, last - 1))
    {x + half - length, x + half}
  end

  defp stub(xs, i, _last, half) do
    x = Enum.at(xs, i)
    length = stub_length(x, Enum.at(xs, i + 1))
    {x - half, x - half + length}
  end

  defp stub_length(x, neighbour), do: min(@beam_stub, abs(neighbour - x) / 2)

  defp beam_item(xa, xb, beam_y, level, sign) do
    offset = -sign * (level - 1) * @beam_step

    %Beam{
      x1: xa,
      y1: beam_y.(xa) + offset,
      x2: xb,
      y2: beam_y.(xb) + offset,
      thickness: -sign * Smufl.default("beamThickness")
    }
  end

  ## Rests

  # Stored rests, then implied ones: a whole-bar rest on an empty staff, and
  # rests in the gaps of each voice on a staff with notes.
  defp rests(measure, geom, voice_counts) do
    stored = Enum.flat_map(measure.rests, &rest(&1, geom, voice_counts[&1.staff]))

    empty_staves =
      for staff <- [:treble, :bass], not Map.has_key?(voice_counts, staff) do
        bar_rest(staff, geom, nil)
      end

    gaps =
      for rest <- Gaps.rests(measure, geom.capacity),
          Map.has_key?(voice_counts, rest.staff),
          item <- rest(rest, geom, voice_counts[rest.staff]),
          do: item

    stored ++ empty_staves ++ gaps
  end

  # A rest filling the bar alone on its staff is drawn as a centered whole
  # rest, whatever the meter.
  defp rest(rest, %MeasureGeometry{capacity: capacity} = geom, voices) do
    case {rest.offset, Duration.ticks(rest.value, rest.dots), voices} do
      {0, ^capacity, 1} -> [bar_rest(rest.staff, geom, rest.id)]
      _partial -> placed_rest(rest, geom, voice_shift(rest.voice, voices))
    end
  end

  defp placed_rest(rest, geom, shift) do
    glyph = Map.fetch!(@rest_glyphs, rest.value)
    x = MeasureGeometry.x_at(geom, rest.offset)
    right = x + Smufl.width(glyph)
    dot_y = Staff.middle(rest.staff) - @half_space + shift

    dots =
      for i <- 0..(rest.dots - 1)//1 do
        glyph(:dot, :augmentationDot, right + @dot_gap + i * @dot_step, dot_y)
      end

    [glyph(:rest, glyph, x, rest_y(rest.value, rest.staff) + shift, rest.id) | dots]
  end

  # With several voices, odd voices' rests move up and even voices' down.
  defp voice_shift(_voice, 1 = _voices), do: 0
  defp voice_shift(voice, _voices) when rem(voice, 2) == 1, do: -@voice_rest_shift
  defp voice_shift(_voice, _voices), do: @voice_rest_shift

  defp rest_y(:whole, staff), do: Staff.top(staff) + @whole_rest_line
  defp rest_y(_value, staff), do: Staff.middle(staff)

  defp bar_rest(staff, geom, id) do
    x = geom.x + (geom.width - Smufl.width(:restWhole)) / 2
    glyph(:rest, :restWhole, x, rest_y(:whole, staff), id)
  end

  ## Items

  defp glyph(role, glyph, x, y, id \\ nil) do
    %Glyph{role: role, glyph: glyph, x: x, y: y, id: id}
  end

  defp line(role, x1, y1, x2, y2, thickness) do
    %Line{role: role, x1: x1, y1: y1, x2: x2, y2: y2, thickness: thickness}
  end
end
