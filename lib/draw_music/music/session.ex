defmodule DrawMusic.Music.Session do
  @moduledoc """
  An editing session over one score: the score and the context it is read
  against, the selection, the clipboard, undo/redo history and whether
  there are unsaved changes. Pure data; `DrawMusicWeb.EditorLive` keeps one
  per open score.

  Every change goes through `edit/2` (or `change_context/3`), which records
  the previous state for undo. The selection only ever holds ids of events
  in the current score.
  """

  alias DrawMusic.Music.{Context, Score}

  defstruct score: nil,
            ctx: %Context{},
            selection: MapSet.new(),
            clipboard: nil,
            undo: [],
            redo: [],
            dirty?: false

  @doc """
  A clean session over `score` read against `ctx`. A score with no measures
  starts with one empty bar, so there is somewhere to write.
  """
  def new(%Score{measures: []}, %Context{} = ctx), do: new(Score.new(), ctx)
  def new(%Score{} = score, %Context{} = ctx), do: %__MODULE__{score: score, ctx: ctx}

  @doc """
  Applies an edit: `fun.(score, ctx)` returns `{:ok, score}`, `{:ok, score,
  extra}` or `{:error, reason}`. On success returns `{:ok, session, extra}`
  (extra is nil when the edit gives none) with the old state undoable.
  """
  def edit(%__MODULE__{} = session, fun) when is_function(fun, 2) do
    case fun.(session.score, session.ctx) do
      {:ok, score} -> {:ok, maybe_record(session, score), nil}
      {:ok, score, extra} -> {:ok, maybe_record(session, score), extra}
      {:error, _reason} = error -> error
    end
  end

  # An edit that changes nothing leaves history and the saved state alone.
  defp maybe_record(%__MODULE__{score: score} = session, score), do: session
  defp maybe_record(session, score), do: record(session, score, session.ctx)

  @doc "Replaces the context (and the score re-read against it), undoably."
  def change_context(%__MODULE__{} = session, %Context{} = ctx, %Score{} = score),
    do: record(session, score, ctx)

  @doc "Steps back one change; does nothing at the start of the history."
  def undo(%__MODULE__{undo: []} = session), do: session

  def undo(%__MODULE__{undo: [{score, ctx} | rest]} = session) do
    %{
      session
      | score: score,
        ctx: ctx,
        undo: rest,
        redo: [{session.score, session.ctx} | session.redo],
        dirty?: true
    }
    |> prune_selection()
  end

  @doc "Re-applies the last undone change; does nothing if there is none."
  def redo(%__MODULE__{redo: []} = session), do: session

  def redo(%__MODULE__{redo: [{score, ctx} | rest]} = session) do
    %{
      session
      | score: score,
        ctx: ctx,
        redo: rest,
        undo: [{session.score, session.ctx} | session.undo],
        dirty?: true
    }
    |> prune_selection()
  end

  @doc "Marks the session as saved."
  def saved(%__MODULE__{} = session), do: %{session | dirty?: false}

  @doc "Selects `ids` (unknown ones are ignored), adding to the selection when `add?`."
  def select(%__MODULE__{} = session, ids, add?) do
    known = session |> event_ids() |> MapSet.intersection(MapSet.new(ids))
    %{session | selection: if(add?, do: MapSet.union(session.selection, known), else: known)}
  end

  @doc "Adds `id` to the selection, or removes it if already selected."
  def toggle(%__MODULE__{} = session, id) do
    if MapSet.member?(session.selection, id),
      do: %{session | selection: MapSet.delete(session.selection, id)},
      else: select(session, [id], true)
  end

  def clear_selection(%__MODULE__{} = session), do: %{session | selection: MapSet.new()}

  @doc "Ids of every note and rest in the score."
  def event_ids(%__MODULE__{score: score}) do
    for m <- score.measures, event <- m.notes ++ m.rests, into: MapSet.new(), do: event.id
  end

  defp record(session, score, ctx) do
    %{
      session
      | score: score,
        ctx: ctx,
        undo: [{session.score, session.ctx} | session.undo],
        redo: [],
        dirty?: true
    }
    |> prune_selection()
  end

  defp prune_selection(session),
    do: %{session | selection: MapSet.intersection(session.selection, event_ids(session))}
end
