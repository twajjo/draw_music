defmodule DrawMusicWeb.TempoTarget do
  @moduledoc """
  What the tempo dialog (`DrawMusicWeb.Editor.TempoDialog`) edits: the
  change (`id`, nil for a new one), the tick it starts at, and the form's
  starting `params` (see `DrawMusicWeb.TempoForm`).

  A rit. or accel. from there may reach as far as `reach` (a tick), where
  the next change starts or the score ends (`until`): `max_beats` beats of
  the time signature, as the form shows it.
  """

  alias DrawMusic.Music.{Context, Score, TempoChange, TempoEditing, TempoMap, Timeline}
  alias DrawMusicWeb.TempoForm

  @enforce_keys [:tick, :params, :reach, :until, :max_beats]
  defstruct [:id, :tick, :params, :reach, :until, :max_beats]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          tick: non_neg_integer(),
          params: %{String.t() => String.t()},
          reach: pos_integer(),
          until: :next_change | :score_end,
          max_beats: String.t()
        }

  @doc """
  A new change where the note or rest `event_id` starts, at the tempo in
  force there. None on the opening beat, whose tempo is the score's
  settings (`:opening_beat`).
  """
  @spec at_event(Score.t(), Context.t(), Ecto.UUID.t()) ::
          {:ok, t()} | {:error, :not_found | :opening_beat}
  def at_event(%Score{} = score, %Context{} = ctx, event_id) do
    case Timeline.start_of(score, ctx, event_id) do
      nil ->
        {:error, :not_found}

      tick ->
        case TempoEditing.changeable?(tick) do
          true ->
            {:ok, new(score, ctx, nil, tick, TempoForm.params(bpm_at(score, ctx, tick), ctx))}

          false ->
            {:error, :opening_beat}
        end
    end
  end

  @doc "An existing change, to edit or delete."
  @spec for_change(Score.t(), Context.t(), TempoChange.t()) :: t()
  def for_change(%Score{} = score, %Context{} = ctx, %TempoChange{} = change) do
    new(score, ctx, change.id, change.tick, TempoForm.params(change, ctx))
  end

  defp bpm_at(score, ctx, tick), do: TempoMap.bpm_at(TempoMap.new(score, ctx), tick)

  defp new(score, ctx, id, tick, params) do
    {reach, until} = TempoEditing.reach(score, ctx, tick, id)

    %__MODULE__{
      id: id,
      tick: tick,
      params: params,
      reach: reach,
      until: until,
      max_beats: TempoForm.beats_text(reach - tick, ctx)
    }
  end
end
