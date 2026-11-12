defmodule DrawMusicWeb.ContextMenu do
  @moduledoc """
  An open right-click menu: the note or rest it acts on (`id`; none for a
  selection), the events its actions apply to (`ids`: the whole selection
  for `:selection`), where it sits on screen, the staff step under the
  pointer (for "Make it a note here"), and whether a tempo change can start
  where the event starts (`tempo?`: not on the opening beat, whose tempo is
  the score's settings).

  The selection decides which menu a right-click opens; see `subject/2`.
  """

  alias DrawMusic.Music.Note
  alias DrawMusicWeb.EditorPlacement

  @enforce_keys [:ids, :kind, :x, :y]
  defstruct [:id, :ids, :kind, :x, :y, :step, tempo?: true]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          ids: [Ecto.UUID.t()],
          kind: :note | :rest | :selection,
          x: number(),
          y: number(),
          step: integer() | nil,
          tempo?: boolean()
        }

  @doc """
  The menu for one note or rest, from the browser's `params` (`x`, `y`
  and, over a staff, `staff` and `step`).
  """
  @spec for_event(struct(), map()) :: t()
  def for_event(event, params) do
    %__MODULE__{
      id: event.id,
      ids: [event.id],
      kind: kind(event),
      x: params["x"],
      y: params["y"],
      step: step(params)
    }
  end

  @doc "The menu for a selection of `ids`, at the browser's `x` and `y`."
  @spec for_selection([Ecto.UUID.t()], map()) :: t()
  def for_selection(ids, params) do
    %__MODULE__{id: nil, ids: ids, kind: :selection, x: params["x"], y: params["y"]}
  end

  @doc """
  What a right-click opens a menu for. The selection decides, wherever
  in the music the click lands: two or more selected, the selection; one,
  that one. With nothing selected it is what was right-clicked
  (`clicked`, nil off the notes), or nothing.
  """
  @spec subject(MapSet.t(Ecto.UUID.t()), Ecto.UUID.t() | nil) ::
          {:selection, [Ecto.UUID.t()]} | {:event, Ecto.UUID.t()} | :none
  def subject(selection, clicked) do
    case {MapSet.to_list(selection), clicked} do
      {[], nil} -> :none
      {[], id} -> {:event, id}
      {[id], _clicked} -> {:event, id}
      {ids, _clicked} -> {:selection, ids}
    end
  end

  defp kind(%Note{}), do: :note
  defp kind(_rest), do: :rest

  # The staff step under the pointer, for "Make it a note here"; nil off
  # the staves.
  defp step(params) do
    case EditorPlacement.parse(Map.merge(%{"measure" => 0, "offset" => 0}, params)) do
      {:ok, target} -> target.step
      :error -> nil
    end
  end
end
