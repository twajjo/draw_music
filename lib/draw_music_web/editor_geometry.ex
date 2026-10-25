defmodule DrawMusicWeb.EditorGeometry do
  @moduledoc """
  What the `ScoreEditor` hook needs to turn a pointer position into a
  musical one, and to draw the armed item as the cursor: JSON payloads
  built from the engraved layout (`DrawMusicWeb.EditorGeometry.Payload`)
  and the armed item (`DrawMusicWeb.EditorGeometry.ArmedPayload`).
  """

  alias DrawMusic.Engraving.{Engraved, Staff}
  alias DrawMusic.Music.{Chords, Context, Duration, Pitch}
  alias DrawMusicWeb.{Armed, EditorPalette, ScoreComponents}

  alias DrawMusicWeb.EditorGeometry.{
    ArmedPayload,
    ChordShape,
    Payload,
    StaffPositions,
    SystemPayload
  }

  @doc "The geometry of an engraved layout, read against `ctx`."
  @spec encode(Engraved.t(), Context.t()) :: Payload.t()
  def encode(%Engraved{} = engraved, %Context{} = ctx) do
    %Payload{
      systems:
        for system <- engraved.systems do
          %SystemPayload{y: system.y, width: system.width, measures: system.measures}
        end,
      staff_top: %StaffPositions{treble: Staff.top(:treble), bass: Staff.top(:bass)},
      top_step: %StaffPositions{treble: Staff.top_step(:treble), bass: Staff.top_step(:bass)},
      padding: ScoreComponents.padding(),
      sf: ctx.sf,
      ppq: Duration.ppq()
    }
  end

  @doc """
  The armed item for the hook: what to draw as the cursor and the time grid
  to snap to (the undotted value's length), or nil when nothing is armed.
  """
  @spec armed(Armed.t() | nil, Context.t()) :: ArmedPayload.t() | nil
  def armed(nil, _ctx), do: nil

  def armed(%Armed{} = armed, %Context{} = ctx) do
    %ArmedPayload{
      kind: armed.kind,
      value: armed.value,
      dots: armed.dots,
      alter: armed.alter,
      glyph: EditorPalette.cursor_glyph(armed),
      grid: Duration.ticks(armed.value),
      chord: chord_shape(armed.chord, ctx)
    }
  end

  # The octave a scale-degree chord is worked out in; only its shape is sent.
  @sample_octave 4

  defp chord_shape({:quality, quality}, _ctx) do
    %ChordShape{
      kind: :quality,
      tones: Enum.map(Chords.intervals(quality), &Tuple.to_list/1),
      suffix: Chords.name(quality)
    }
  end

  defp chord_shape({:degree, degree}, %Context{sf: sf, mode: mode}) do
    {tonic, _pitch_class} = Pitch.tonic(sf, mode)
    root_letter = Integer.mod(tonic + degree - 1, Pitch.steps_per_octave())
    root_step = Pitch.step(root_letter, @sample_octave)
    {:ok, pitches} = Chords.diatonic(sf, mode, root_step)

    %ChordShape{
      kind: :degree,
      root_letter: root_letter,
      tones: for({step, alter} <- pitches, do: [step - root_step, alter]),
      suffix: degree_suffix(Chords.quality_of(pitches)),
      numeral: Chords.numeral(mode, degree)
    }
  end

  defp chord_shape(nil, _ctx), do: nil

  defp degree_suffix(nil), do: ""
  defp degree_suffix(quality), do: Chords.name(quality)
end
