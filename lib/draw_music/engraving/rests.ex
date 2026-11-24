defmodule DrawMusic.Engraving.Rests do
  @moduledoc """
  Lays out one measure's rests as drawing items (`DrawMusic.Engraving.Item`):
  the rests stored in the measure, a whole-bar rest on each empty staff,
  and the rests that fill the gaps between notes (`DrawMusic.Music.Gaps`).

  A rest that fills the bar alone on its staff is drawn as a whole rest
  centred in the bar, whatever the meter. With several voices on a staff,
  odd voices' rests move up and even voices' rests move down.
  """

  alias DrawMusic.Engraving.{Glyph, Item, MeasureGeometry, Smufl, Staff}
  alias DrawMusic.Music.{Context, Duration, Gaps, Measure}

  @half_space 0.5
  @dot_gap 0.3
  @dot_step 0.5
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

  @doc """
  The staves `measure` shows as a single whole rest centred in the bar
  (whatever the meter): a staff with nothing on it, or one rest filling the
  bar in a single voice. The editor hit-tests those rests where they're
  drawn, not at beat 1.
  """
  @spec bar_rest_staves(Measure.t(), pos_integer()) :: [:treble | :bass]
  def bar_rest_staves(%Measure{} = measure, capacity) do
    voice_counts = Measure.voice_counts(measure)

    for staff <- [:treble, :bass],
        not Map.has_key?(voice_counts, staff) or
          Enum.any?(
            measure.rests,
            &(&1.staff == staff and bar_rest?(&1, capacity, voice_counts[staff]))
          ),
        do: staff
  end

  @doc "The width of the whole rest drawn for a bar rest (staff spaces)."
  @spec bar_rest_width() :: float()
  def bar_rest_width, do: Smufl.width(:restWhole)

  @doc """
  Items for the rests of `measure` laid out in `geom`: stored rests, then a
  whole-bar rest on each empty staff, then rests in the gaps of each voice
  on a staff with notes.
  """
  @spec items(Measure.t(), MeasureGeometry.t(), Context.t()) :: [Item.t()]
  def items(%Measure{} = measure, %MeasureGeometry{} = geom, %Context{} = ctx) do
    voice_counts = Measure.voice_counts(measure)
    stored = Enum.flat_map(measure.rests, &rest(&1, geom, voice_counts[&1.staff]))

    empty_staves =
      for staff <- [:treble, :bass], not Map.has_key?(voice_counts, staff) do
        bar_rest(staff, geom, nil)
      end

    gaps =
      for rest <- Gaps.rests(measure, geom.capacity, ctx),
          Map.has_key?(voice_counts, rest.staff),
          item <- rest(rest, geom, voice_counts[rest.staff]),
          do: item

    stored ++ empty_staves ++ gaps
  end

  # Centred in the bar; the editor's hit-testing mirrors this
  # (`barRestX` in assets/js/score_editor/geometry.js).
  defp bar_rest(staff, geom, id) do
    x = geom.x + (geom.width - bar_rest_width()) / 2
    glyph(:restWhole, x, rest_y(:whole, staff), id)
  end

  defp bar_rest?(rest, capacity, voices) do
    match?({0, ^capacity, 1}, {rest.offset, Duration.ticks(rest.value, rest.dots), voices})
  end

  defp glyph(glyph, x, y, id) do
    %Glyph{role: :rest, glyph: glyph, x: x, y: y, id: id}
  end

  defp placed_rest(rest, geom, shift) do
    glyph = Map.fetch!(@rest_glyphs, rest.value)
    x = MeasureGeometry.x_at(geom, rest.offset)
    right = x + Smufl.width(glyph)
    dot_y = Staff.middle(rest.staff) - @half_space + shift

    dots =
      for i <- 0..(rest.dots - 1)//1 do
        %Glyph{role: :dot, glyph: :augmentationDot, x: right + @dot_gap + i * @dot_step, y: dot_y}
      end

    [glyph(glyph, x, rest_y(rest.value, rest.staff) + shift, rest.id) | dots]
  end

  defp rest(rest, %MeasureGeometry{capacity: capacity} = geom, voices) do
    if bar_rest?(rest, capacity, voices),
      do: [bar_rest(rest.staff, geom, rest.id)],
      else: placed_rest(rest, geom, voice_shift(rest.voice, voices))
  end

  defp rest_y(:whole, staff), do: Staff.top(staff) + @whole_rest_line
  defp rest_y(_value, staff), do: Staff.middle(staff)

  defp voice_shift(_voice, 1 = _voices), do: 0
  defp voice_shift(voice, _voices) when rem(voice, 2) == 1, do: -@voice_rest_shift
  defp voice_shift(_voice, _voices), do: @voice_rest_shift
end
