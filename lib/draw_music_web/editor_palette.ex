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
    sixty_fourth: :note64thUp,
    hundred_twenty_eighth: :note128thUp,
    two_hundred_fifty_sixth: :note256thUp
  }

  @rest_glyphs %{
    whole: :restWhole,
    half: :restHalf,
    quarter: :restQuarter,
    eighth: :rest8th,
    sixteenth: :rest16th,
    thirty_second: :rest32nd,
    sixty_fourth: :rest64th,
    hundred_twenty_eighth: :rest128th,
    two_hundred_fifty_sixth: :rest256th
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
  it is (with its dots and accidental). In chord mode a note value changes
  the chord's length and keeps the chord.
  """
  @spec arm(Armed.t() | nil, term(), term()) :: {:ok, Armed.t()} | :error
  def arm(armed, kind_name, value_name) do
    with kind when not is_nil(kind) <- Map.get(@kinds, kind_name),
         value when not is_nil(value) <- value(value_name) do
      case armed do
        %Armed{kind: ^kind, value: ^value} ->
          {:ok, armed}

        %Armed{kind: :chord} when kind == :note ->
          {:ok,
           %{armed | value: value, dots: min(armed.dots, Enum.max(Duration.dot_counts(value)))}}

        _ ->
          {:ok, %Armed{kind: kind, value: value}}
      end
    else
      _ -> :error
    end
  end

  @doc "Parses a chord pick: a quality or a scale degree; `:error` for anything else."
  @spec chord(map()) :: {:ok, Armed.chord()} | :error
  def chord(%{"quality" => name}) do
    case quality(name) do
      nil -> :error
      quality -> {:ok, {:quality, quality}}
    end
  end

  def chord(%{"degree" => degree}) when degree in ~w(1 2 3 4 5 6 7),
    do: {:ok, {:degree, String.to_integer(degree)}}

  def chord(_params), do: :error

  @doc """
  Chord mode: places `chord` at the armed note's length, dots and
  accidental (a quarter with nothing armed), whichever was picked first.
  Picking the chord that is already on turns chord mode off.
  """
  @spec arm_chord(Armed.t() | nil, Armed.chord()) :: Armed.t()
  def arm_chord(%Armed{kind: :chord, chord: chord} = armed, chord), do: single_notes(armed)

  def arm_chord(%Armed{kind: kind} = armed, chord) when kind in [:note, :chord],
    do: %{armed | kind: :chord, chord: chord}

  def arm_chord(_armed, chord), do: %Armed{kind: :chord, value: :quarter, chord: chord}

  @doc "Turns chord mode off, keeping the length, dots and accidental."
  @spec single_notes(Armed.t() | nil) :: Armed.t() | nil
  def single_notes(%Armed{kind: :chord} = armed), do: %{armed | kind: :note, chord: nil}
  def single_notes(armed), do: armed

  @doc "Arms the tie tool."
  @spec arm_tie() :: Armed.t()
  def arm_tie, do: %Armed{kind: :tie, value: :quarter}

  @doc """
  Flips the duration row between notes and rests, converting an armed note
  or rest. An armed chord becomes a rest: chord mode doesn't apply to rests.
  """
  @spec toggle_rest(:note | :rest, Armed.t() | nil) :: {:note | :rest, Armed.t() | nil}
  def toggle_rest(row_kind, armed) do
    row_kind = if row_kind == :rest, do: :note, else: :rest

    armed =
      case armed do
        %Armed{kind: kind} when kind in [:note, :rest, :chord] ->
          %{armed | kind: row_kind, chord: nil}

        other ->
          other
      end

    {row_kind, armed}
  end

  @doc "Toggles one dot on the armed item (never on a 256th, which takes none)."
  @spec toggle_dot(Armed.t()) :: Armed.t()
  def toggle_dot(%Armed{dots: 0, value: value} = armed) do
    %{armed | dots: if(Duration.dots_allowed?(value, 1), do: 1, else: 0)}
  end

  def toggle_dot(%Armed{} = armed), do: %{armed | dots: 0}

  @doc "Whether the armed item can take a dot."
  @spec dottable?(Armed.t() | nil) :: boolean()
  def dottable?(%Armed{value: value}) when not is_nil(value), do: Duration.dots_allowed?(value, 1)
  def dottable?(_armed), do: true

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
end
