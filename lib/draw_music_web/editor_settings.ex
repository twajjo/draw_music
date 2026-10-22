defmodule DrawMusicWeb.EditorSettings do
  @moduledoc """
  The score settings form's data (key, time signature, tempo, pickup), shared
  by the editor's settings panel and the new composition form, and what a
  save stores. Settings are checked with the `Version` changeset.
  """

  alias DrawMusic.Library.{Key, Version}
  alias DrawMusic.Music.{Context, Editing, Session}

  @doc "The settings form's params for a context and tempo marking."
  @spec params(Context.t(), String.t() | nil) :: %{String.t() => String.t()}
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
  @spec validate(map()) ::
          {:ok, {-7..7, :major | :minor}, map()} | {:error, keyword()} | :error
  def validate(params) do
    with {:ok, key} <- Key.from_slug(params["key"] || "") do
      changeset = Version.changeset(%Version{number: 1}, form_attrs(params))

      if changeset.valid? do
        fields = Ecto.Changeset.apply_changes(changeset)

        {:ok, key,
         Map.take(fields, [:time_num, :time_den, :time_symbol, :tempo_bpm, :pickup_ticks])}
      else
        {:error, form_errors(changeset.errors)}
      end
    end
  end

  @doc "Version attrs from the form's params: the form asks for pickup beats, not ticks."
  @spec form_attrs(map()) :: %{String.t() => term()}
  def form_attrs(params) do
    params
    |> Map.take(~w(time_num time_den time_symbol tempo_bpm tempo_text))
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
  Applies validated `fields` to the session: the notes keep their times and
  re-flow into the new bars (undoably). Unchanged settings leave the
  session as it is.
  """
  @spec apply(Session.t(), map()) :: {:ok, Session.t()} | {:error, Editing.reason()}
  def apply(%Session{} = session, fields) do
    rebar(session, struct(session.ctx, fields))
  end

  defp rebar(%Session{ctx: ctx} = session, ctx), do: {:ok, session}

  defp rebar(session, ctx) do
    with {:ok, score} <- Editing.rebar_to(session.score, session.ctx, ctx) do
      {:ok, Session.change_context(session, ctx, score)}
    end
  end

  @doc "What a save stores: the score and the settings it is read against."
  @spec version_attrs(Session.t(), String.t() | nil) :: map()
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
  @spec tempo_text(String.t() | nil) :: String.t() | nil
  def tempo_text(value) when value in [nil, ""], do: nil
  def tempo_text(value), do: value
end
