defmodule DrawMusicWeb.EditorPlacement do
  @moduledoc """
  Placing the armed palette item where the user clicked.

  `parse/1` validates a `place` event's params (they come from the
  browser); `place/5` composes the `Editing` calls for a note, rest or
  chord, first making room in Insert mode.
  """

  alias DrawMusic.Music.{Chords, Duration, Editing, Pitch, Timeline}

  @staves %{"treble" => :treble, "bass" => :bass}

  @doc """
  `{:ok, %{measure, offset, staff, step, alter}}` from event params, or
  `:error`. `alter` is nil unless the user held a modifier.
  """
  def parse(params) do
    with {:ok, measure} <- non_neg(params["measure"]),
         {:ok, offset} <- non_neg(params["offset"]),
         staff when not is_nil(staff) <- Map.get(@staves, params["staff"]),
         {:ok, step} <- int(params["step"]),
         {:ok, alter} <- optional_alter(params["alter"]) do
      {:ok, %{measure: measure, offset: offset, staff: staff, step: step, alter: alter}}
    else
      _ -> :error
    end
  end

  @doc """
  Places `armed` at `target`. The alteration is the user's modifier, else
  the palette's accidental, else the key's. In Insert mode, time is first
  inserted on the target's staff.
  """
  def place(score, ctx, armed, target, insert?) do
    with {:ok, start} <- start_of(score, ctx, target),
         {:ok, score} <- make_room(score, ctx, armed, target, start, insert?) do
      put(score, ctx, armed, target)
    end
  end

  defp start_of(score, ctx, %{measure: measure, offset: offset}) do
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

  defp put(score, ctx, %{kind: :note} = armed, target),
    do:
      Editing.place_note(
        score,
        ctx,
        target.measure,
        Map.merge(event_attrs(armed, target), pitch(ctx, armed, target))
      )

  defp put(score, ctx, %{kind: :rest} = armed, target),
    do: Editing.place_rest(score, ctx, target.measure, event_attrs(armed, target))

  defp put(score, ctx, %{kind: :chord, chord: chord} = armed, target) do
    with {:ok, pitches} <- chord_pitches(ctx, chord, pitch(ctx, armed, target)),
         do: Editing.place_chord(score, ctx, target.measure, event_attrs(armed, target), pitches)
  end

  defp put(_score, _ctx, _armed, _target), do: {:error, :not_found}

  defp event_attrs(armed, target),
    do: %{staff: target.staff, offset: target.offset, value: armed.value, dots: armed.dots}

  defp pitch(ctx, armed, %{step: step, alter: alter}) do
    %{step: step, alter: alter || armed.alter || Pitch.key_alter(ctx.sf, Pitch.letter(step))}
  end

  defp chord_pitches(_ctx, {:quality, quality}, %{step: step, alter: alter}),
    do: Chords.build(step, alter, quality)

  # The numeral's root is the key's degree in the clicked note's octave.
  defp chord_pitches(ctx, {:degree, degree}, %{step: step}) do
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
