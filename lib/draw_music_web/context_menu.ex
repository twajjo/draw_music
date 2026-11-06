defmodule DrawMusicWeb.ContextMenu do
  @moduledoc """
  An open right-click menu: the event it was opened on (`id`), the events
  its actions apply to (`ids`: the whole selection for `:selection`), where
  it sits on screen, and the staff step that was clicked (for "Make it a
  note here").
  """

  alias DrawMusic.Music.Note
  alias DrawMusicWeb.EditorPlacement

  @enforce_keys [:id, :ids, :kind, :x, :y]
  defstruct [:id, :ids, :kind, :x, :y, :step]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          ids: [Ecto.UUID.t()],
          kind: :note | :rest | :selection,
          x: number(),
          y: number(),
          step: integer() | nil
        }

  @doc """
  The menu for a right-click on `event`, from the browser's `params` (`x`,
  `y` and, over a staff, `staff` and `step`). Right-clicking a selected
  event opens the menu for the whole `selection`.
  """
  @spec new(MapSet.t(Ecto.UUID.t()), struct(), map()) :: t()
  def new(selection, event, params) do
    {kind, ids} = target(selection, event)

    %__MODULE__{
      id: event.id,
      ids: ids,
      kind: kind,
      x: params["x"],
      y: params["y"],
      step: step(params)
    }
  end

  defp kind(%Note{}), do: :note
  defp kind(_rest), do: :rest

  # The clicked staff step, for "Make it a note here"; nil off the staves.
  defp step(params) do
    case EditorPlacement.parse(Map.merge(%{"measure" => 0, "offset" => 0}, params)) do
      {:ok, target} -> target.step
      :error -> nil
    end
  end

  defp target(selection, event) do
    case MapSet.member?(selection, event.id) do
      true -> {:selection, MapSet.to_list(selection)}
      false -> {kind(event), [event.id]}
    end
  end
end
