defmodule DrawMusicWeb.EditorPalette do
  @moduledoc """
  The palette's state: what is armed for placing (a `DrawMusicWeb.Armed`,
  or nil), and whether the duration row shows notes or rests.

  Event params come from the browser, so values are only ever looked up,
  never converted to atoms.
  """

  alias DrawMusic.Engraving.Smufl
  alias DrawMusic.Music.{Chords, Duration}
  alias DrawMusicWeb.Armed

  @values Map.new(Duration.values(), &{Atom.to_string(&1), &1})
  @qualities Map.new(Chords.qualities(), &{Atom.to_string(&1), &1})
  @kinds %{"note" => :note, "rest" => :rest}

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

  @doc "Parses a note value name; nil for anything else."
  @spec value(term()) :: Duration.value() | nil
  def value(name), do: Map.get(@values, name)

  @doc "Parses a chord quality name; nil for anything else."
  @spec quality(term()) :: Chords.quality() | nil
  def quality(name), do: Map.get(@qualities, name)

  @doc ~s(Parses an accidental: "1" sharp, "-1" flat, "0" natural; nil for anything else.)
  @spec alter(term()) :: -1..1 | nil
  def alter(name) when name in ~w(1 -1 0), do: String.to_integer(name)
  def alter(_name), do: nil

  @doc """
  Arms a note or rest of `value`. Arming what is already armed keeps it as
  it is (a double-click sends two clicks before the lock).
  """
  @spec arm(Armed.t() | nil, term(), term(), boolean()) :: {:ok, Armed.t()} | :error
  def arm(armed, kind_name, value_name, locked? \\ false) do
    with kind when not is_nil(kind) <- Map.get(@kinds, kind_name),
         value when not is_nil(value) <- value(value_name) do
      case armed do
        %Armed{kind: ^kind, value: ^value} -> {:ok, %{armed | locked?: armed.locked? or locked?}}
        _ -> {:ok, %Armed{kind: kind, value: value, locked?: locked?}}
      end
    else
      _ -> :error
    end
  end

  @doc "Arms a chord: a quality or a scale degree, at the armed value (else a quarter)."
  @spec arm_chord(Armed.t() | nil, map()) :: {:ok, Armed.t()} | :error
  def arm_chord(armed, %{"quality" => name}) do
    case quality(name) do
      nil -> :error
      quality -> {:ok, %Armed{kind: :chord, value: value_of(armed), chord: {:quality, quality}}}
    end
  end

  def arm_chord(armed, %{"degree" => degree}) when degree in ~w(1 2 3 4 5 6 7),
    do:
      {:ok,
       %Armed{kind: :chord, value: value_of(armed), chord: {:degree, String.to_integer(degree)}}}

  def arm_chord(_armed, _params), do: :error

  @doc "Arms the tie tool."
  @spec arm_tie() :: Armed.t()
  def arm_tie, do: %Armed{kind: :tie, value: :quarter}

  @doc "Flips the duration row between notes and rests, converting an armed note or rest."
  @spec toggle_rest(:note | :rest, Armed.t() | nil) :: {:note | :rest, Armed.t() | nil}
  def toggle_rest(row_kind, armed) do
    row_kind = if row_kind == :rest, do: :note, else: :rest

    armed =
      case armed do
        %Armed{kind: kind} when kind in [:note, :rest] -> %{armed | kind: row_kind}
        other -> other
      end

    {row_kind, armed}
  end

  @doc "Toggles one dot on the armed item."
  @spec toggle_dot(Armed.t()) :: Armed.t()
  def toggle_dot(%Armed{dots: 0} = armed), do: %{armed | dots: 1}
  def toggle_dot(%Armed{} = armed), do: %{armed | dots: 0}

  @doc "Sets the armed item's accidental; choosing the same one again clears it."
  @spec set_accidental(Armed.t(), -2..2) :: Armed.t()
  def set_accidental(%Armed{alter: alter} = armed, alter), do: %{armed | alter: nil}
  def set_accidental(%Armed{} = armed, alter), do: %{armed | alter: alter}

  @doc "The character drawn as the cursor for an armed item (nil for the tie tool)."
  @spec cursor_glyph(Armed.t()) :: String.t() | nil
  def cursor_glyph(%Armed{kind: :note, value: value}) do
    Smufl.char(Map.fetch!(@note_glyphs, value))
  end

  def cursor_glyph(%Armed{kind: :rest, value: value}) do
    Smufl.char(Map.fetch!(@rest_glyphs, value))
  end

  def cursor_glyph(%Armed{kind: :chord}), do: Smufl.char(:noteheadBlack)
  def cursor_glyph(%Armed{kind: :tie}), do: nil

  defp value_of(%Armed{kind: kind, value: value}) when kind in [:note, :rest, :chord], do: value
  defp value_of(_armed), do: :quarter
end
