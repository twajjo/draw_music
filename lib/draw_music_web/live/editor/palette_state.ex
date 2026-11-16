defmodule DrawMusicWeb.Editor.PaletteState do
  @moduledoc """
  The palette's state, kept by `DrawMusicWeb.EditorLive` and shown by
  `DrawMusicWeb.Editor.Palette`: the armed item (nil when nothing is),
  which row the palette shows (notes or rests), and whether placing
  inserts (the default) or overlays. Changed by the palette's
  `{:palette, changes}` intents.
  """

  alias DrawMusicWeb.Armed

  defstruct armed: nil, row_kind: :note, insert?: true

  @type t :: %__MODULE__{
          armed: Armed.t() | nil,
          row_kind: :note | :rest,
          insert?: boolean()
        }

  @doc "`palette` with the `changes` a `{:palette, changes}` intent names."
  @spec change(t(), map()) :: t()
  def change(%__MODULE__{} = palette, changes) do
    struct(palette, Map.take(changes, [:armed, :row_kind, :insert?]))
  end
end
