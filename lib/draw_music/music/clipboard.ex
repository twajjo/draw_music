defmodule DrawMusic.Music.Clipboard do
  @moduledoc """
  Copied notes and rests: entries timed from the earliest one, so a paste
  can put them anywhere. `copy/3` and `paste/4` are edits (through
  `DrawMusic.Music.Editing`, whose moduledoc has the score's rules).
  """

  alias DrawMusic.Music.{Context, Editing, Entry, Fillers, Score, Ties, Timeline}
  alias DrawMusic.Music.Editing.Rebuild

  defstruct entries: []

  @type t :: %__MODULE__{entries: [Entry.t()]}

  @doc """
  Copies the given events. Positions are kept relative to the earliest
  one; ties to notes outside the selection are dropped.
  """
  @spec copy(Score.t(), Context.t(), [Editing.id()]) :: t()
  def copy(%Score{} = score, %Context{} = ctx, ids) do
    ids = MapSet.new(ids)
    {selected, _others} = Entry.select(Timeline.flatten(score, ctx), ids)

    origin =
      selected
      |> Enum.map(& &1.start)
      |> Enum.min(fn -> 0 end)

    %__MODULE__{
      entries:
        Enum.map(selected, fn entry ->
          %{entry | start: entry.start - origin, event: Ties.drop_outside(entry.event, ids)}
        end)
    }
  end

  @doc """
  Pastes a clipboard from `copy/3` starting at absolute tick `at`, with
  fresh ids; tied pieces of a lone note that now follow each other merge.
  Returns the new ids.
  """
  @spec paste(Score.t(), Context.t(), t(), non_neg_integer()) ::
          {:ok, Score.t(), [Editing.id()]} | {:error, Editing.reason()}
  def paste(%Score{} = score, %Context{} = ctx, %__MODULE__{entries: entries}, at)
      when is_integer(at) and at >= 0 do
    fresh = Map.new(entries, &{&1.event.id, Ecto.UUID.generate()})

    pasted =
      Enum.map(entries, fn entry ->
        event = Ties.renumber(%{Fillers.claim(entry.event) | id: fresh[entry.event.id]}, fresh)
        %{entry | start: entry.start + at, event: event}
      end)

    entries =
      Ties.merge(Rebuild.clear_rests_under(Timeline.flatten(score, ctx), pasted) ++ pasted)

    with {:ok, score} <- Rebuild.rebuild(score, ctx, entries), do: {:ok, score, Map.values(fresh)}
  end
end
