defmodule DrawMusicWeb.EditorPlacement do
  @moduledoc """
  Placing the armed palette item where the user clicked.

  `parse/1` validates a `place` event's params (they come from the
  browser) into a `DrawMusicWeb.PlacementTarget`; `place/5` composes the
  `Editing` calls for a note, rest or chord, first making room in Insert
  mode.
  """

  alias DrawMusic.Music.{Chords, Context, Duration, Editing, Pitch, Placement, Score, Timeline}
  alias DrawMusicWeb.{Armed, PlacementTarget}

  @staves %{"treble" => :treble, "bass" => :bass}

  @doc """
  The target of a `place` event, or `:error` for anything malformed.
  `alter` is nil unless the user held a modifier.
  """
  @spec parse(map()) :: {:ok, PlacementTarget.t()} | :error
  def parse(params) do
    with {:ok, measure} <- non_neg(params["measure"]),
         {:ok, offset} <- non_neg(params["offset"]),
         staff when not is_nil(staff) <- Map.get(@staves, params["staff"]),
         {:ok, step} <- int(params["step"]),
         {:ok, alter} <- optional_alter(params["alter"]) do
      {:ok,
       %PlacementTarget{measure: measure, offset: offset, staff: staff, step: step, alter: alter}}
    else
      _ -> :error
    end
  end

  @doc """
  Places `armed` at `target`. The alteration is the user's modifier, else
  the palette's accidental, else the key's. In Insert mode, time is first
  inserted on the target's staff.
  """
  @spec place(Score.t(), Context.t(), Armed.t(), PlacementTarget.t(), boolean()) ::
          {:ok, Score.t(), Ecto.UUID.t() | [Ecto.UUID.t()]} | {:error, Editing.reason()}
  def place(
        %Score{} = score,
        %Context{} = ctx,
        %Armed{} = armed,
        %PlacementTarget{} = target,
        insert?
      ) do
    with {:ok, start} <- start_of(score, ctx, target),
         {:ok, score} <- make_room(score, ctx, armed, target, start, insert?) do
      put(score, ctx, armed, target)
    end
  end

  defp start_of(score, ctx, %PlacementTarget{measure: measure, offset: offset}) do
    case Enum.at(Timeline.bars(score, ctx), measure) do
      {start, _capacity} -> {:ok, start + offset}
      nil -> {:error, :no_such_measure}
    end
  end

  defp make_room(score, _ctx, _armed, _target, _start, false), do: {:ok, score}

  defp make_room(score, ctx, armed, target, start, true),
    do:
      Editing.insert_time(
        score,
        ctx,
        start,
        Duration.ticks(armed.value, armed.dots),
        target.staff
      )

  defp put(score, ctx, %Armed{kind: :note} = armed, target) do
    {step, alter} = pitch(ctx, armed, target)

    Editing.place_note(score, ctx, target.measure, %{
      placement(armed, target)
      | step: step,
        alter: alter
    })
  end

  defp put(score, ctx, %Armed{kind: :rest} = armed, target),
    do: Editing.place_rest(score, ctx, target.measure, placement(armed, target))

  defp put(score, ctx, %Armed{kind: :chord, chord: chord} = armed, target) do
    with {:ok, pitches} <- chord_pitches(ctx, chord, pitch(ctx, armed, target)),
         do: Editing.place_chord(score, ctx, target.measure, placement(armed, target), pitches)
  end

  defp put(_score, _ctx, _armed, _target), do: {:error, :not_found}

  defp placement(armed, target),
    do: %Placement{
      staff: target.staff,
      offset: target.offset,
      value: armed.value,
      dots: armed.dots
    }

  defp pitch(ctx, armed, %PlacementTarget{step: step, alter: alter}),
    do: {step, alter || armed.alter || Pitch.key_alter(ctx.sf, Pitch.letter(step))}

  defp chord_pitches(_ctx, {:quality, quality}, {step, alter}),
    do: Chords.build(step, alter, quality)

  # The numeral's root is the key's degree in the clicked note's octave.
  defp chord_pitches(ctx, {:degree, degree}, {step, _alter}) do
    {tonic, _pc} = Pitch.tonic(ctx.sf, ctx.mode)
    root_letter = Integer.mod(tonic + degree - 1, 7)
    Chords.diatonic(ctx.sf, ctx.mode, Pitch.step(root_letter, Pitch.octave(step)))
  end

  defp non_neg(value) do
    case int(value) do
      {:ok, n} when n >= 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp int(n) when is_integer(n), do: {:ok, n}

  defp int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp int(_value), do: :error

  defp optional_alter(nil), do: {:ok, nil}

  defp optional_alter(value) do
    case int(value) do
      {:ok, alter} when alter in -2..2 -> {:ok, alter}
      _ -> :error
    end
  end
end
