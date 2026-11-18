defmodule DrawMusic.Music.Entry do
  @moduledoc """
  A note or rest placed on the score's absolute time axis: `start` and
  `ticks` count from the beginning of the piece (see
  `DrawMusic.Music.Timeline`). Edits work on entries, then re-bar them.
  """

  alias DrawMusic.Music.{Note, Rest}

  @enforce_keys [:kind, :start, :ticks, :event]
  defstruct [:kind, :start, :ticks, :event]

  @type t :: %__MODULE__{
          kind: :note | :rest,
          start: non_neg_integer(),
          ticks: pos_integer(),
          event: Note.t() | Rest.t()
        }

  @doc """
  Which chord an entry belongs to: its staff, voice and start. Notes with
  the same key sound together as one chord (a voice's notes that start
  together have the same length, or the edit was refused).
  """
  @spec chord_key(t()) :: {Note.staff(), Note.voice(), non_neg_integer()}
  def chord_key(%__MODULE__{event: event, start: start}), do: {event.staff, event.voice, start}

  @doc "The tick where an entry ends (and the next may start)."
  @spec end_tick(t()) :: non_neg_integer()
  def end_tick(%__MODULE__{start: start, ticks: ticks}), do: start + ticks

  @doc "The entry for event `id` among `entries`."
  @spec find([t()], Ecto.UUID.t()) :: {:ok, t()} | {:error, :not_found}
  def find(entries, id) do
    case Enum.find(entries, &(&1.event.id == id)) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  @doc "The entries for events among `ids`, in order; at least one must be found."
  @spec find_all([t()], Enumerable.t()) :: {:ok, [t(), ...]} | {:error, :not_found}
  def find_all(entries, ids) do
    case select(entries, ids) do
      {[], _rest} -> {:error, :not_found}
      {found, _rest} -> {:ok, found}
    end
  end

  @doc "`entries` with the one for event `id` replaced by `replacements` (none, one or more)."
  @spec replace([t()], Ecto.UUID.t(), [t()]) :: [t()]
  def replace(entries, id, replacements) do
    Enum.flat_map(entries, fn
      %{event: %{id: ^id}} -> replacements
      entry -> [entry]
    end)
  end

  @doc "`entries` split into those for events among `ids` and the rest, in order."
  @spec select([t()], Enumerable.t()) :: {[t()], [t()]}
  def select(entries, ids) do
    ids = MapSet.new(ids)
    Enum.split_with(entries, &(&1.event.id in ids))
  end
end
