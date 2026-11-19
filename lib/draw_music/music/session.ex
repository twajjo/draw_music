defmodule DrawMusic.Music.Session do
  @moduledoc """
  An editing session over one score: the score and the context it is read
  against, the selection, the insertion cursor, the clipboard, undo/redo
  history and whether there are unsaved changes. Pure data;
  `DrawMusicWeb.EditorLive` keeps one per open score.

  Every change goes through `edit/2` (or `change_context/3`), which records
  the previous state for undo. The selection only ever holds ids of events
  in the current score.

  The **cursor** is a tick: where the next paste (and, with a MIDI
  keyboard, the next entry) goes. A click on empty music puts it there
  (`put_cursor/2`); selecting one note or rest puts it just after it. It
  never sits past the score's end: edits, undo and redo bring it back.
  """

  alias DrawMusic.Music.{Context, Editing, Entry, Note, Rest, Score, Timeline}

  defstruct score: nil,
            ctx: %Context{},
            selection: MapSet.new(),
            cursor: nil,
            clipboard: nil,
            undo: [],
            redo: [],
            dirty?: false

  @type t :: %__MODULE__{
          score: Score.t(),
          ctx: Context.t(),
          selection: MapSet.t(Ecto.UUID.t()),
          cursor: non_neg_integer() | nil,
          clipboard: DrawMusic.Music.Clipboard.t() | nil,
          undo: [{Score.t(), Context.t()}],
          redo: [{Score.t(), Context.t()}],
          dirty?: boolean()
        }

  @doc "Replaces the context (and the score re-read against it), undoably."
  @spec change_context(t(), Context.t(), Score.t()) :: t()
  def change_context(%__MODULE__{} = session, %Context{} = ctx, %Score{} = score) do
    record(session, score, ctx)
  end

  @spec clear_selection(t()) :: t()
  def clear_selection(%__MODULE__{} = session), do: %{session | selection: MapSet.new()}

  @doc "Narrows the selection to its earliest event; an empty selection stays empty."
  @spec collapse_selection(t()) :: t()
  def collapse_selection(%__MODULE__{score: score, ctx: ctx, selection: selection} = session) do
    first =
      score
      |> Timeline.flatten(ctx)
      |> Enum.filter(&(&1.event.id in selection))
      |> Enum.min_by(& &1.start, fn -> nil end)

    case first do
      nil -> session
      entry -> %{session | selection: MapSet.new([entry.event.id])}
    end
  end

  @doc "Copies the selection to the clipboard; with nothing selected, nothing changes."
  @spec copy(t()) :: t()
  def copy(%__MODULE__{selection: selection} = session) do
    case MapSet.size(selection) do
      0 ->
        session

      _some ->
        %{session | clipboard: Editing.copy(session.score, session.ctx, selection_ids(session))}
    end
  end

  @doc """
  Applies an edit: `fun.(score, ctx)` returns `{:ok, score}`, `{:ok, score,
  extra}` or `{:error, reason}`. On success returns `{:ok, session, extra}`
  (extra is nil when the edit gives none) with the old state undoable.
  """
  @spec edit(t(), (Score.t(), Context.t() ->
                     {:ok, Score.t()} | {:ok, Score.t(), term()} | {:error, term()})) ::
          {:ok, t(), term()} | {:error, term()}
  def edit(%__MODULE__{} = session, fun) when is_function(fun, 2) do
    case fun.(session.score, session.ctx) do
      {:ok, score} -> {:ok, maybe_record(session, score), nil}
      {:ok, score, extra} -> {:ok, maybe_record(session, score), extra}
      {:error, _reason} = error -> error
    end
  end

  @doc "Ids of every note, rest and tempo change in the score."
  @spec event_ids(t()) :: MapSet.t(Ecto.UUID.t())
  def event_ids(%__MODULE__{score: score}) do
    events = for m <- score.measures, event <- m.notes ++ m.rests, do: event.id
    MapSet.new(events ++ Enum.map(score.tempos, & &1.id))
  end

  @doc "The note or rest with `id`, or nil."
  @spec find_event(t(), Ecto.UUID.t()) :: Note.t() | Rest.t() | nil
  def find_event(%__MODULE__{score: score}, id) do
    Enum.find_value(score.measures, fn m -> Enum.find(m.notes ++ m.rests, &(&1.id == id)) end)
  end

  @doc """
  A clean session over `score` read against `ctx`. A score with no measures
  starts with one empty bar, so there is somewhere to write. Gaps are filled
  with filler rests, so every rest drawn can be selected.
  """
  @spec new(Score.t(), Context.t()) :: t()
  def new(%Score{measures: []}, %Context{} = ctx), do: new(Score.new(), ctx)

  def new(%Score{} = score, %Context{} = ctx) do
    %__MODULE__{score: Editing.fill_rests(score, ctx), ctx: ctx}
  end

  @doc """
  Where to paste: tick `at` if one is given, else the cursor, else
  straight after the selection, else the start. Never past the end of the
  score: the browser's numbers are untrusted.
  """
  @spec paste_at(t(), term()) :: non_neg_integer()
  def paste_at(%__MODULE__{score: score, ctx: ctx} = session, at) do
    min(wanted_paste_at(session, at), Timeline.end_tick(score, ctx))
  end

  @doc "Puts the cursor at tick `at` (no further than the score's end)."
  @spec put_cursor(t(), non_neg_integer()) :: t()
  def put_cursor(%__MODULE__{} = session, at) when is_integer(at) and at >= 0 do
    clamp_cursor(%{session | cursor: at})
  end

  @doc """
  Puts the cursor just after the event (or the latest-ending of the
  events) `ids`, as after placing a note, rest or chord; ids not in the
  score leave it where it is.
  """
  @spec put_cursor_after(t(), Ecto.UUID.t() | [Ecto.UUID.t()]) :: t()
  def put_cursor_after(%__MODULE__{score: score, ctx: ctx} = session, ids) do
    case Entry.find_all(Timeline.flatten(score, ctx), List.wrap(ids)) do
      {:ok, entries} -> %{session | cursor: entries |> Enum.map(&Entry.end_tick/1) |> Enum.max()}
      {:error, :not_found} -> session
    end
  end

  @doc "Re-applies the last undone change; does nothing if there is none."
  @spec redo(t()) :: t()
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
    |> clamp_cursor()
  end

  @doc "Marks the session as saved."
  @spec saved(t()) :: t()
  def saved(%__MODULE__{} = session), do: %{session | dirty?: false}

  @doc """
  Selects `ids` (unknown ones are ignored), adding to the selection when
  `add?`. When one note or rest ends up selected, the cursor goes just
  after it.
  """
  @spec select(t(), [Ecto.UUID.t()], boolean()) :: t()
  def select(%__MODULE__{} = session, ids, add?) do
    known =
      session
      |> event_ids()
      |> MapSet.intersection(MapSet.new(ids))

    follow_selection(%{session | selection: selected(session.selection, known, add?)})
  end

  @doc "The selected notes and rests (not tempo changes)."
  @spec selected_events(t()) :: [Note.t() | Rest.t()]
  def selected_events(%__MODULE__{score: score, selection: selection}) do
    for m <- score.measures, event <- m.notes ++ m.rests, event.id in selection, do: event
  end

  @doc "The selected ids, as a list."
  @spec selection_ids(t()) :: [Ecto.UUID.t()]
  def selection_ids(%__MODULE__{selection: selection}), do: MapSet.to_list(selection)

  @doc "Adds `id` to the selection, or removes it if already selected."
  @spec toggle(t(), Ecto.UUID.t()) :: t()
  def toggle(%__MODULE__{} = session, id) do
    if MapSet.member?(session.selection, id) do
      %{session | selection: MapSet.delete(session.selection, id)}
    else
      select(session, [id], true)
    end
  end

  @doc "Steps back one change; does nothing at the start of the history."
  @spec undo(t()) :: t()
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
    |> clamp_cursor()
  end

  # A cursor past the score's end (after an edit shortened it) goes back to
  # the end.
  defp clamp_cursor(%__MODULE__{cursor: nil} = session), do: session

  defp clamp_cursor(%__MODULE__{cursor: cursor, score: score, ctx: ctx} = session) do
    %{session | cursor: min(cursor, Timeline.end_tick(score, ctx))}
  end

  # One note or rest selected: the cursor goes just after it.
  defp follow_selection(%__MODULE__{selection: selection} = session) do
    with [id] <- MapSet.to_list(selection),
         {:ok, entry} <- Entry.find(Timeline.flatten(session.score, session.ctx), id) do
      %{session | cursor: Entry.end_tick(entry)}
    else
      _none_or_several -> session
    end
  end

  # An edit that changes nothing leaves history and the saved state alone.
  defp maybe_record(%__MODULE__{score: score} = session, score), do: session
  defp maybe_record(session, score), do: record(session, score, session.ctx)

  defp prune_selection(session) do
    %{session | selection: MapSet.intersection(session.selection, event_ids(session))}
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
    |> clamp_cursor()
  end

  defp selected(current, known, true = _add?), do: MapSet.union(current, known)
  defp selected(_current, known, false), do: known

  defp wanted_paste_at(_session, at) when is_integer(at) and at >= 0, do: at
  defp wanted_paste_at(%__MODULE__{cursor: cursor}, _at) when is_integer(cursor), do: cursor

  defp wanted_paste_at(%__MODULE__{score: score, ctx: ctx, selection: selection}, _at) do
    score
    |> Timeline.flatten(ctx)
    |> Enum.filter(&(&1.event.id in selection))
    |> Enum.map(&Entry.end_tick/1)
    |> Enum.max(fn -> 0 end)
  end
end
