defmodule DrawMusicWeb.TempoForm do
  @moduledoc """
  The tempo dialog's form: the tempo (BPM), and for a rit. or accel. the
  tempo it reaches and over how many beats (of the time signature). Params
  come from the browser as strings.

  A rit. or accel. can't contradict itself or its neighbours: it reaches a
  different tempo, and it ends at the latest where the next change starts
  or the score ends (the target's `reach`, see `DrawMusicWeb.TempoTarget`).
  """

  alias DrawMusic.Music.{Context, TempoChange}
  alias DrawMusicWeb.TempoTarget

  @doc "How many beats of the time signature `ticks` are, as the form shows them."
  @spec beats_text(non_neg_integer(), Context.t()) :: String.t()
  def beats_text(ticks, ctx) do
    beats = ticks / Context.beat_ticks(ctx)
    if beats == trunc(beats), do: to_string(trunc(beats)), else: to_string(Float.round(beats, 2))
  end

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

  @doc """
  What a gradual change does, from the params' tempos: "rit." when it
  slows down, "accel." when it speeds up, nil while that isn't known.
  """
  @spec ramp_word(map()) :: String.t() | nil
  def ramp_word(params) do
    with {bpm, ""} <- Integer.parse(params["bpm"] || ""),
         {to_bpm, ""} <- Integer.parse(params["to_bpm"] || "") do
      cond do
        to_bpm < bpm -> "rit."
        to_bpm > bpm -> "accel."
        true -> nil
      end
    else
      _not_numbers -> nil
    end
  end

  @doc """
  The change the params describe, starting at the target's tick (keeping
  its id), or form errors by field.
  """
  @spec validate(map(), TempoTarget.t(), Context.t()) ::
          {:ok, TempoChange.t()} | {:error, keyword()}
  def validate(params, %TempoTarget{} = target, ctx) do
    range = Context.tempo_range()
    bpm = tempo(params["bpm"], range)

    {to_bpm, to_tick} =
      case params["gradual"] do
        "true" -> {other_tempo(params["to_bpm"], bpm, range), span(params["beats"], target, ctx)}
        _steady -> {nil, nil}
      end

    errors =
      for {field, {:error, message}} <- [bpm: bpm, to_bpm: to_bpm, beats: to_tick],
          do: {field, {message, []}}

    case errors do
      [] ->
        {:ok,
         %TempoChange{
           id: target.id,
           tick: target.tick,
           bpm: bpm,
           to_bpm: to_bpm,
           to_tick: to_tick
         }}

      errors ->
        {:error, errors}
    end
  end

  # A gradual change's end tempo: in range, and not the tempo it starts at.
  defp other_tempo(text, bpm, range) do
    case tempo(text, range) do
      ^bpm when is_integer(bpm) -> {:error, "must differ from the starting tempo"}
      to_bpm -> to_bpm
    end
  end

  # Beats may be fractional (a dotted beat), and run at most to the
  # target's reach.
  defp span(text, target, ctx) do
    {max_beats, ""} = Float.parse(target.max_beats)

    case Float.parse(text || "") do
      {beats, ""} when beats > max_beats ->
        {:error, "can be at most #{target.max_beats}, #{until(target.until)}"}

      {beats, ""} when beats > 0 ->
        ticks = round(beats * Context.beat_ticks(ctx))
        if ticks > 0, do: min(target.tick + ticks, target.reach), else: too_short()

      _other ->
        too_short()
    end
  end

  defp tempo(text, range) do
    case Integer.parse(text || "") do
      {bpm, ""} when bpm >= range.first and bpm <= range.last -> bpm
      _other -> {:error, "must be #{range.first}–#{range.last}"}
    end
  end

  defp too_short, do: {:error, "must be more than 0"}

  defp until(:next_change), do: "up to the next tempo change"
  defp until(:score_end), do: "up to the end of the score"
end
