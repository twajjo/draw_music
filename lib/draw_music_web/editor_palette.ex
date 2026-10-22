defmodule DrawMusicWeb.EditorPalette do
  @moduledoc """
  The palette's state: what is armed for placing, and whether the duration
  row shows notes or rests.

  The armed item is `nil` or
  `%{kind: :note | :rest | :chord | :tie, value, dots, alter, chord, locked?}`:
  `alter` is nil (follow the key) or -2..2, `chord` is nil,
  `{:quality, quality}` or `{:degree, 1..7}`, and a locked item stays armed
  after placing. Event params come from the browser, so values are only
  ever looked up, never converted to atoms.
  """

  alias DrawMusic.Engraving.Smufl
  alias DrawMusic.Music.{Chords, Duration}

  @values Map.new(Duration.values(), &{Atom.to_string(&1), &1})
  @qualities Map.new(Chords.qualities(), &{Atom.to_string(&1), &1})
  @kinds %{"note" => :note, "rest" => :rest}

  @doc "Parses a note value name; nil for anything else."
  def value(name), do: Map.get(@values, name)

  @doc "Parses a chord quality name; nil for anything else."
  def quality(name), do: Map.get(@qualities, name)

  @doc """
  Arms a note or rest of `value`. Arming what is already armed keeps it as
  it is (a double-click sends two clicks before the lock).
  """
  def arm(armed, kind_name, value_name, locked? \\ false) do
    with kind when not is_nil(kind) <- Map.get(@kinds, kind_name),
         value when not is_nil(value) <- value(value_name) do
      case armed do
        %{kind: ^kind, value: ^value} -> {:ok, %{armed | locked?: armed.locked? or locked?}}
        _ -> {:ok, new(kind, value, locked?)}
      end
    else
      _ -> :error
    end
  end

  @doc "Arms a chord: a quality or a scale degree, at the armed value (else a quarter)."
  def arm_chord(armed, %{"quality" => name}) do
    case quality(name) do
      nil -> :error
      quality -> {:ok, %{new(:chord, value_of(armed), false) | chord: {:quality, quality}}}
    end
  end

  def arm_chord(armed, %{"degree" => degree}) when degree in ~w(1 2 3 4 5 6 7),
    do:
      {:ok, %{new(:chord, value_of(armed), false) | chord: {:degree, String.to_integer(degree)}}}

  def arm_chord(_armed, _params), do: :error

  @doc "Arms the tie tool."
  def arm_tie, do: new(:tie, :quarter, false)

  @doc "Flips the duration row between notes and rests, converting an armed note or rest."
  def toggle_rest(row_kind, armed) do
    row_kind = if row_kind == :rest, do: :note, else: :rest

    armed =
      case armed do
        %{kind: kind} when kind in [:note, :rest] -> %{armed | kind: row_kind}
        other -> other
      end

    {row_kind, armed}
  end

  @doc "Toggles one dot on the armed item."
  def toggle_dot(%{dots: 0} = armed), do: %{armed | dots: 1}
  def toggle_dot(%{} = armed), do: %{armed | dots: 0}

  @doc "Sets the armed item's accidental; choosing the same one again clears it."
  def set_accidental(%{alter: alter} = armed, alter), do: %{armed | alter: nil}
  def set_accidental(%{} = armed, alter), do: %{armed | alter: alter}

  @doc ~s(Parses an accidental: "1" sharp, "-1" flat, "0" natural.)
  def alter(name) when name in ~w(1 -1 0), do: String.to_integer(name)
  def alter(_name), do: nil

  @note_glyphs %{
    whole: :noteWhole,
    half: :noteHalfUp,
    quarter: :noteQuarterUp,
    eighth: :note8thUp,
    sixteenth: :note16thUp,
    thirty_second: :note32ndUp,
    sixty_fourth: :note64thUp
  }

  @rest_glyphs %{
    whole: :restWhole,
    half: :restHalf,
    quarter: :restQuarter,
    eighth: :rest8th,
    sixteenth: :rest16th,
    thirty_second: :rest32nd,
    sixty_fourth: :rest64th
  }

  @doc "The character drawn as the cursor for an armed item (nil for the tie tool)."
  def cursor_glyph(%{kind: :note, value: value}), do: Smufl.char(Map.fetch!(@note_glyphs, value))
  def cursor_glyph(%{kind: :rest, value: value}), do: Smufl.char(Map.fetch!(@rest_glyphs, value))
  def cursor_glyph(%{kind: :chord}), do: Smufl.char(:noteheadBlack)
  def cursor_glyph(%{kind: :tie}), do: nil

  defp new(kind, value, locked?),
    do: %{kind: kind, value: value, dots: 0, alter: nil, chord: nil, locked?: locked?}

  defp value_of(%{kind: kind, value: value}) when kind in [:note, :rest, :chord], do: value
  defp value_of(_armed), do: :quarter
end
