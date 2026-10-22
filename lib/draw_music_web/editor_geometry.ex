defmodule DrawMusicWeb.EditorGeometry do
  @moduledoc """
  What the `ScoreEditor` hook needs to turn a pointer position into a
  musical one, as JSON-ready maps: each system's place on the page and its
  measures' tick ↔ x geometry (see `DrawMusic.Engraving.Layout`), the
  staves' vertical positions, and the key. Units are staff spaces, as in
  the score's SVG viewBox.
  """

  alias DrawMusic.Engraving.Staff
  alias DrawMusic.Music.{Context, Duration}
  alias DrawMusicWeb.{EditorPalette, ScoreComponents}

  @doc "The geometry of an engraved layout read against `ctx`."
  def encode(engraved, %Context{} = ctx) do
    %{
      systems:
        for system <- engraved.systems do
          %{
            y: system.y,
            width: system.width,
            measures:
              Enum.map(
                system.measures,
                &Map.take(&1, [:index, :x, :width, :start_tick, :capacity, :content_x, :scale])
              )
          }
        end,
      staff_top: %{treble: Staff.top(:treble), bass: Staff.top(:bass)},
      top_step: %{treble: Staff.top_step(:treble), bass: Staff.top_step(:bass)},
      padding: ScoreComponents.padding(),
      sf: ctx.sf,
      ppq: Duration.ppq()
    }
  end

  @doc """
  The armed item for the hook: what to draw as the cursor and the time grid
  to snap to (the undotted value's length), or nil when nothing is armed.
  """
  def armed(nil), do: nil

  def armed(armed) do
    %{
      kind: armed.kind,
      value: armed.value,
      dots: armed.dots,
      alter: armed.alter,
      locked: armed.locked?,
      glyph: EditorPalette.cursor_glyph(armed),
      grid: Duration.ticks(armed.value)
    }
  end
end
