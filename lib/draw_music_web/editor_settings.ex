defmodule DrawMusicWeb.EditorSettings do
  @moduledoc """
  The score settings form's data (key, time signature, tempo, pickup,
  playback instrument), shared by the editor's settings panel and the new
  composition form, and what a save stores. Settings are checked with the
  `Version` changeset.
  """

  alias DrawMusic.Library.{Key, Version}
  alias DrawMusic.Music.{Context, Editing, Session}

  @fields [:time_num, :time_den, :time_symbol, :tempo_bpm, :pickup_ticks, :instrument]

  @doc "The settings form's params for a context, tempo marking and GM instrument."
  @spec params(Context.t(), String.t() | nil, 0..127) :: %{String.t() => String.t()}
  def params(%Context{} = ctx, tempo_text, instrument) do
    %{
      "key" => Key.slug(ctx.sf, ctx.mode),
      "time_num" => to_string(ctx.time_num),
      "time_den" => to_string(ctx.time_den),
      "time_symbol" => to_string(ctx.time_symbol),
      "tempo_bpm" => to_string(ctx.tempo_bpm),
      "tempo_text" => tempo_text || "",
      "pickup_beats" => to_string(div(ctx.pickup_ticks, Context.beat_ticks(ctx))),
      "instrument" => to_string(instrument)
    }
  end

  @doc """
  Checks submitted settings: `{:ok, key, fields}` with the `{sf, mode}` key
  and the fields they set (the Context's, plus `:instrument`),
  `{:error, errors}` (keyed by form field) or `:error` for an unknown key.
  """
  @spec validate(map()) ::
          {:ok, {-7..7, :major | :minor}, map()} | {:error, keyword()} | :error
  def validate(params) do
    with {:ok, key} <- Key.from_slug(params["key"] || "") do
      case Version.changeset(%Version{number: 1}, form_attrs(params)) do
        %Ecto.Changeset{valid?: true} = changeset ->
          {:ok, key, Map.take(Ecto.Changeset.apply_changes(changeset), @fields)}

        changeset ->
          {:error, form_errors(changeset.errors)}
      end
    end
  end

  @doc "Version attrs from the form's params: the form asks for pickup beats, not ticks."
  @spec form_attrs(map()) :: %{String.t() => term()}
  def form_attrs(params) do
    params
    |> Map.take(~w(time_num time_den time_symbol tempo_bpm tempo_text instrument))
    |> Map.put("pickup_ticks", pickup_ticks(params))
  end

  @doc "Version changeset errors keyed by form field."
  @spec form_errors(keyword()) :: keyword()
  def form_errors(errors) do
    Enum.map(errors, fn
      {:pickup_ticks, error} -> {:pickup_beats, error}
      error -> error
    end)
  end

  defp pickup_ticks(params) do
    with {beats, ""} <- Integer.parse(params["pickup_beats"] || ""),
         {den, ""} <- Integer.parse(params["time_den"] || ""),
         true <- den in Context.time_denominators() do
      beats * Context.beat_ticks(%Context{time_den: den})
    else
      _ -> 0
    end
  end

  @doc """
  Applies validated `fields` to the session (undoably). A new time
  signature or pickup moves the bar lines: the notes keep their times and
  re-flow into the new bars. Anything else, like the tempo, leaves the
  score as it is. Unchanged settings leave the session as it is.
  """
  @spec apply(Session.t(), map()) :: {:ok, Session.t()} | {:error, Editing.reason()}
  def apply(%Session{} = session, fields) do
    rebar(session, struct(session.ctx, fields))
  end

  defp rebar(%Session{ctx: ctx} = session, ctx), do: {:ok, session}

  defp rebar(%Session{ctx: old} = session, ctx) do
    case bars(old) == bars(ctx) do
      true -> {:ok, Session.change_context(session, ctx, session.score)}
      false -> rebar_score(session, ctx)
    end
  end

  defp rebar_score(session, ctx) do
    with {:ok, score} <- Editing.rebar_to(session.score, session.ctx, ctx) do
      {:ok, Session.change_context(session, ctx, score)}
    end
  end

  # What decides where the bar lines fall.
  defp bars(%Context{} = ctx), do: {ctx.time_num, ctx.time_den, ctx.pickup_ticks}

  @doc "What a save stores: the score, the settings it is read against, and its instrument."
  @spec version_attrs(Session.t(), String.t() | nil, 0..127) :: map()
  def version_attrs(%Session{score: score, ctx: ctx}, tempo_text, instrument) do
    %{
      score: score,
      time_num: ctx.time_num,
      time_den: ctx.time_den,
      time_symbol: ctx.time_symbol,
      tempo_bpm: ctx.tempo_bpm,
      tempo_text: tempo_text,
      pickup_ticks: ctx.pickup_ticks,
      instrument: instrument
    }
  end

  @doc "A blank tempo marking is none."
  @spec tempo_text(String.t() | nil) :: String.t() | nil
  def tempo_text(value) when value in [nil, ""], do: nil
  def tempo_text(value), do: value
end
