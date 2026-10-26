defmodule DrawMusicWeb.TempoForm do
  @moduledoc """
  The tempo dialog's form: the tempo (BPM), and for a rit. or accel. the
  tempo it reaches and over how many beats (of the time signature). Params
  come from the browser as strings.
  """

  alias DrawMusic.Music.{Context, TempoChange}

  @doc "Form params for an existing change, or a new one at `bpm`."
  @spec params(TempoChange.t() | pos_integer(), Context.t()) :: %{String.t() => String.t()}
  def params(%TempoChange{to_tick: nil} = change, _ctx) do
    %{"bpm" => to_string(change.bpm), "gradual" => "false", "to_bpm" => "", "beats" => ""}
  end

  def params(%TempoChange{} = change, ctx) do
    %{
      "bpm" => to_string(change.bpm),
      "gradual" => "true",
      "to_bpm" => to_string(change.to_bpm),
      "beats" => beats_text(change.to_tick - change.tick, ctx)
    }
  end

  def params(bpm, _ctx) when is_integer(bpm) do
    %{"bpm" => to_string(bpm), "gradual" => "false", "to_bpm" => "", "beats" => "4"}
  end

  defp beats_text(ticks, ctx) do
    beats = ticks / Context.beat_ticks(ctx)
    if beats == trunc(beats), do: to_string(trunc(beats)), else: to_string(Float.round(beats, 2))
  end

  @doc """
  The change the params describe, starting at `tick` (keeping `id`), or
  form errors by field.
  """
  @spec validate(map(), non_neg_integer(), Ecto.UUID.t() | nil, Context.t()) ::
          {:ok, TempoChange.t()} | {:error, keyword()}
  def validate(params, tick, id, ctx) do
    range = Context.tempo_range()
    bpm = tempo(params["bpm"], range)

    {to_bpm, to_tick} =
      case params["gradual"] do
        "true" -> {tempo(params["to_bpm"], range), span(params["beats"], tick, ctx)}
        _steady -> {:none, :none}
      end

    errors =
      [
        {:bpm, bpm},
        {:to_bpm, to_bpm},
        {:beats, to_tick}
      ]
      |> Enum.flat_map(fn
        {field, :error} -> [{field, {message(field, range), []}}]
        _ok -> []
      end)

    case errors do
      [] ->
        {:ok,
         %TempoChange{id: id, tick: tick, bpm: bpm, to_bpm: none(to_bpm), to_tick: none(to_tick)}}

      errors ->
        {:error, errors}
    end
  end

  defp none(:none), do: nil
  defp none(value), do: value

  defp tempo(text, range) do
    case Integer.parse(text || "") do
      {bpm, ""} -> if bpm in range, do: bpm, else: :error
      _other -> :error
    end
  end

  # Beats may be fractional (a dotted beat): at least a sixteenth of one.
  defp span(text, tick, ctx) do
    case Float.parse(text || "") do
      {beats, ""} when beats > 0 ->
        ticks = round(beats * Context.beat_ticks(ctx))
        if ticks > 0, do: tick + ticks, else: :error

      _other ->
        :error
    end
  end

  defp message(:beats, _range), do: "must be more than 0"
  defp message(_tempo, range), do: "must be #{range.first}–#{range.last}"
end
