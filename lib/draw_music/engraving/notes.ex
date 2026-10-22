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

  alias DrawMusic.Music.{Accidentals, BeamGroup, Beaming, Context, Duration, Measure, Stems}

  @stem_length 3.5
  @min_beamed_stem 2.5
  @max_beam_rise 1.0
  # Distance between beam levels: beam thickness plus beam spacing.
  @beam_step 0.75
  @beam_stub 1.0
  @dot_gap 0.3
  @dot_step 0.5
  @accidental_gap 0.25
  @accidental_column 1.2
  # Accidentals closer than this many steps go in different columns.
  @accidental_clearance 6
  @voice_rest_shift 2

  @rest_glyphs %{
    whole: :restWhole,
    half: :restHalf,
    quarter: :restQuarter,
    eighth: :rest8th,
    sixteenth: :rest16th,
    thirty_second: :rest32nd,
    sixty_fourth: :rest64th
  }

  @flag_glyphs %{
    {1, :up} => :flag8thUp,
    {1, :down} => :flag8thDown,
    {2, :up} => :flag16thUp,
    {2, :down} => :flag16thDown,
    {3, :up} => :flag32ndUp,
    {3, :down} => :flag32ndDown,
    {4, :up} => :flag64thUp,
    {4, :down} => :flag64thDown
  }

  @accidental_glyphs %{
    -2 => :accidentalDoubleFlat,
    -1 => :accidentalFlat,
    0 => :accidentalNatural,
    1 => :accidentalSharp,
    2 => :accidentalDoubleSharp
  }

  @doc """
  Items for `measure` (number `index`) laid out in `geom` (`x`, `width`,
  `capacity`, `content_x` and `scale` in staff spaces per tick). `tied_in`
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
      for g <- groups, offset <- g.offsets, into: %{}, do: {{g.staff, g.voice, offset}, g}

    accidentals = Accidentals.displayed(measure, ctx.sf, tied_in)

    laid =
      Map.new(chords, fn {{staff, voice, _offset} = key, notes} ->
        steps = stem_steps(notes, group_of[key], chords)
        dir = Stems.direction(staff, steps, voice, voice_counts[staff])
        {key, chord(notes, key, dir, geom, accidentals)}
      end)

    stems =
      for {key, chord} <- laid,
          not Map.has_key?(group_of, key),
          item <- free_stem(chord),
          do: item

    items =
      Enum.flat_map(laid, fn {_key, chord} -> chord.items end) ++
        stems ++ Enum.flat_map(groups, &beam(&1, laid)) ++ rests(measure, geom, voice_counts)

    anchors = for {_key, chord} <- laid, anchor <- chord.anchors, into: %{}, do: anchor
    {items, anchors}
  end

  # A beamed chord's stem direction is decided by its whole beam group.
  defp stem_steps(notes, nil, _chords), do: Enum.map(notes, & &1.step)

  defp stem_steps(_notes, group, chords),
    do: for(o <- group.offsets, n <- chords[{group.staff, group.voice, o}], do: n.step)

  defp voice_counts(measure) do
    (measure.notes ++ measure.rests)
    |> Enum.group_by(& &1.staff, & &1.voice)
    |> Map.new(fn {staff, voices} -> {staff, voices |> Enum.uniq() |> length()} end)
  end

  ## Chords

  defp chord([first | _] = notes, {staff, _voice, offset}, dir, geom, accidentals) do
    glyph = notehead(first.value)
    width = Smufl.width(glyph)
    x = geom.content_x + offset * geom.scale
    heads = heads(notes, staff, dir, x, width)
    left = heads |> Enum.map(& &1.x) |> Enum.min()
    right = (heads |> Enum.map(& &1.x) |> Enum.max()) + width
    ys = Enum.map(heads, & &1.y)

    %ChordLayout{
      staff: staff,
      dir: dir,
      value: first.value,
      glyph: glyph,
      x: x,
      top_y: Enum.min(ys),
      bottom_y: Enum.max(ys),
      items:
        Enum.map(heads, &glyph(:notehead, glyph, &1.x, &1.y, &1.note.id)) ++
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
    order = if dir == :up, do: :asc, else: :desc

    notes
    |> Enum.sort_by(& &1.step, order)
    |> Enum.map_reduce(nil, fn note, previous ->
      moved =
        previous != nil and abs(note.step - previous.note.step) == 1 and not previous.moved

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
      y = if Staff.line?(head.note.step), do: head.y - 0.5, else: head.y
      glyph(:dot, :augmentationDot, right + @dot_gap + i * @dot_step, y)
    end
  end

  # Top to bottom, each accidental goes in the first column whose last sign
  # is far enough above it.
  defp accidentals(heads, left, shown) do
    heads
    |> Enum.filter(&Map.has_key?(shown, &1.note.id))
    |> Enum.sort_by(& &1.note.step, :desc)
    |> Enum.map_reduce([], fn head, columns ->
      glyph = Map.fetch!(@accidental_glyphs, shown[head.note.id])
      column = Enum.find_index(columns, &(&1 - head.note.step >= @accidental_clearance))

      {column, columns} =
        if column,
          do: {column, List.replace_at(columns, column, head.note.step)},
          else: {length(columns), columns ++ [head.note.step]}

      right = left - @accidental_gap - column * @accidental_column
      {glyph(:accidental, glyph, right - Smufl.width(glyph), head.y), columns}
    end)
    |> elem(0)
  end

  ## Stems, flags and beams

  defp free_stem(%ChordLayout{value: :whole}), do: []

  defp free_stem(chord) do
    flags = Duration.flags(chord.value)
    length = @stem_length + max(flags - 2, 0) * @beam_step
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

  defp stem(x, base, tip, dir),
    do: %{line(:stem, x, base, x, tip, Smufl.default("stemThickness")) | dir: dir}

  defp flag(0, _dir, _x, _tip), do: []

  defp flag(flags, dir, x, tip),
    do: [
      glyph(
        :flag,
        Map.fetch!(@flag_glyphs, {flags, dir}),
        x - Smufl.default("stemThickness") / 2,
        tip
      )
    ]

  # The beam runs between the ideal stem tips of the first and last chords,
  # its slope clamped, then moves away from the notes until every stem is
  # long enough.
  defp beam(%BeamGroup{staff: staff, voice: voice, offsets: offsets}, laid) do
    chords = Enum.map(offsets, &Map.fetch!(laid, {staff, voice, &1}))
    dir = hd(chords).dir
    sign = if dir == :up, do: -1, else: 1
    attachments = Enum.map(chords, &stem_attachment/1)
    extremes = Enum.map(chords, &if(dir == :up, do: &1.top_y, else: &1.bottom_y))
    levels = Enum.map(chords, &Duration.flags(&1.value))

    {x1, _} = hd(attachments)
    {xn, _} = List.last(attachments)
    y1 = hd(extremes) + sign * @stem_length

    rise =
      (List.last(extremes) + sign * @stem_length - y1)
      |> max(-@max_beam_rise)
      |> min(@max_beam_rise)

    sloped = fn x -> y1 + rise * (x - x1) / max(xn - x1, 1.0e-6) end

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
      for level <- 1..Enum.max(levels),
          {xa, xb} <- level_spans(xs, levels, level, half),
          do: beam_item(xa, xb, beam_y, level, sign)

    stems ++ beams
  end

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
        x = Enum.at(xs, i)
        neighbour = if i == last, do: Enum.at(xs, i - 1), else: Enum.at(xs, i + 1)
        stub = min(@beam_stub, abs(neighbour - x) / 2)
        if i == last, do: {x + half - stub, x + half}, else: {x - half, x - half + stub}

      [{_flags, i} | _] = run ->
        {_flags, j} = List.last(run)
        {Enum.at(xs, i) - half, Enum.at(xs, j) + half}
    end)
  end

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

  defp rests(measure, geom, voice_counts) do
    stored = Enum.flat_map(measure.rests, &rest(&1, geom, voice_counts[&1.staff]))

    implied =
      for staff <- [:treble, :bass],
          not Map.has_key?(voice_counts, staff),
          do: bar_rest(staff, geom, nil)

    stored ++ implied
  end

  # A rest filling the bar alone on its staff is drawn as a centered whole
  # rest, whatever the meter. With several voices, odd voices' rests move up
  # and even voices' down.
  defp rest(rest, geom, voices) do
    if rest.offset == 0 and Duration.ticks(rest.value, rest.dots) == geom.capacity and voices == 1 do
      [bar_rest(rest.staff, geom, rest.id)]
    else
      shift =
        cond do
          voices == 1 -> 0
          rem(rest.voice, 2) == 1 -> -@voice_rest_shift
          true -> @voice_rest_shift
        end

      glyph = Map.fetch!(@rest_glyphs, rest.value)

      y =
        if(rest.value == :whole, do: Staff.top(rest.staff) + 1, else: Staff.middle(rest.staff)) +
          shift

      x = geom.content_x + rest.offset * geom.scale
      right = x + Smufl.width(glyph)

      dots =
        for i <- 0..(rest.dots - 1)//1,
            do:
              glyph(
                :dot,
                :augmentationDot,
                right + @dot_gap + i * @dot_step,
                Staff.middle(rest.staff) - 0.5 + shift
              )

      [glyph(:rest, glyph, x, y, rest.id) | dots]
    end
  end

  defp bar_rest(staff, geom, id) do
    x = geom.x + (geom.width - Smufl.width(:restWhole)) / 2
    glyph(:rest, :restWhole, x, Staff.top(staff) + 1, id)
  end

  ## Items

  defp glyph(role, glyph, x, y, id \\ nil),
    do: %Glyph{role: role, glyph: glyph, x: x, y: y, id: id}

  defp line(role, x1, y1, x2, y2, thickness),
    do: %Line{role: role, x1: x1, y1: y1, x2: x2, y2: y2, thickness: thickness}
end
