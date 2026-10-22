defmodule DrawMusicWeb.EditorGeometry do
  @moduledoc """
  What the `ScoreEditor` hook needs to turn a pointer position into a
  musical one, and to draw the armed item as the cursor: JSON payloads
  built from the engraved layout (`DrawMusicWeb.EditorGeometry.Payload`)
  and the armed item (`DrawMusicWeb.EditorGeometry.ArmedPayload`).
  """

  alias DrawMusic.Engraving.{Engraved, Staff}
  alias DrawMusic.Music.{Context, Duration}
  alias DrawMusicWeb.{Armed, EditorPalette, ScoreComponents}
  alias DrawMusicWeb.EditorGeometry.{ArmedPayload, Payload, StaffPositions, SystemPayload}

  @doc "The geometry of an engraved layout read against `ctx`."
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
  @spec armed(Armed.t() | nil) :: ArmedPayload.t() | nil
  def armed(nil), do: nil

  def armed(%Armed{} = armed) do
    %ArmedPayload{
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
