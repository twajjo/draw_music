defmodule DrawMusicWeb.EditorSettings do
  @moduledoc """
  The score settings panel's data (key, time signature, tempo, pickup) and
  what a save stores. Settings are checked with the `Version` changeset, as
  on the new composition form.
  """

  alias DrawMusic.Library.{Key, Version}
  alias DrawMusic.Music.{Context, Editing, Session}

  @time_denominators ~w(1 2 4 8 16 32 64)

  @doc "The settings form's params for a context and tempo marking."
  def params(%Context{} = ctx, tempo_text) do
    %{
      "key" => Key.slug(ctx.sf, ctx.mode),
      "time_num" => to_string(ctx.time_num),
      "time_den" => to_string(ctx.time_den),
      "time_symbol" => to_string(ctx.time_symbol),
      "tempo_bpm" => to_string(ctx.tempo_bpm),
      "tempo_text" => tempo_text || "",
      "pickup_beats" => to_string(div(ctx.pickup_ticks, Context.beat_ticks(ctx)))
    }
  end

  @doc """
  Checks submitted settings: `{:ok, key, fields}` with the `{sf, mode}` key
  and the Context fields they set, `{:error, errors}` (keyed by form field)
  or `:error` for an unknown key.
  """
  def validate(params) do
    with {:ok, key} <- Key.from_slug(params["key"] || "") do
      changeset = Version.changeset(%Version{number: 1}, version_params(params))

      if changeset.valid? do
        fields = Ecto.Changeset.apply_changes(changeset)

        {:ok, key,
         Map.take(fields, [:time_num, :time_den, :time_symbol, :tempo_bpm, :pickup_ticks])}
      else
        {:error, Enum.map(changeset.errors, &form_error/1)}
      end
    end
  end

  # The form asks for pickup beats; the version stores ticks.
  defp form_error({:pickup_ticks, error}), do: {:pickup_beats, error}
  defp form_error(error), do: error

  defp version_params(params) do
    params
    |> Map.take(~w(time_num time_den time_symbol tempo_bpm tempo_text))
    |> Map.put("pickup_ticks", pickup_ticks(params))
  end

  defp pickup_ticks(params) do
    with {beats, ""} <- Integer.parse(params["pickup_beats"] || ""),
         den when den in @time_denominators <- params["time_den"] do
      beats * Context.beat_ticks(%Context{time_den: String.to_integer(den)})
    else
      _ -> 0
    end
  end

  @doc """
  Applies validated `fields` to the session: the notes keep their times and
  re-flow into the new bars (undoably). Unchanged settings leave the
  session as it is.
  """
  def apply(%Session{} = session, fields) do
    ctx = struct(session.ctx, fields)
    if ctx == session.ctx, do: {:ok, session}, else: rebar(session, ctx)
  end

  defp rebar(session, ctx) do
    with {:ok, score} <- Editing.rebar_to(session.score, session.ctx, ctx),
         do: {:ok, Session.change_context(session, ctx, score)}
  end

  @doc "What a save stores: the score and the settings it is read against."
  def version_attrs(%Session{score: score, ctx: ctx}, tempo_text) do
    %{
      score: score,
      time_num: ctx.time_num,
      time_den: ctx.time_den,
      time_symbol: ctx.time_symbol,
      tempo_bpm: ctx.tempo_bpm,
      tempo_text: tempo_text,
      pickup_ticks: ctx.pickup_ticks
    }
  end

  @doc "A blank tempo marking is none."
  def tempo_text(value) when value in [nil, ""], do: nil
  def tempo_text(value), do: value
end
