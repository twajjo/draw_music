defmodule DrawMusic.Music.TempoMarking do
  @moduledoc """
  The tempo markings a score can open with. A marking is one tempo, with
  the established word for it in each language that has one, so choosing
  a marking also shows what it is called elsewhere. One of its words is
  printed over the first bar; the tempo itself is the score's BPM.

  The words are the usual dictionary equivalents: tempo terms don't
  translate exactly, and many have no counterpart in some languages.
  Every marking has an English word, which also gives its meaning.

  Each word belongs to one marking only, so a stored word (see
  `DrawMusic.Library.Version`) tells both the marking and its language.

  Most markings have a usual tempo (`bpm`), which choosing the marking
  suggests as the starting tempo; the BPM can then be set to anything.
  """

  @enforce_keys [:english]
  defstruct [:italian, :german, :french, :english, :bpm]

  @type language :: :italian | :german | :french | :english

  @type t :: %__MODULE__{
          italian: String.t() | nil,
          german: String.t() | nil,
          french: String.t() | nil,
          english: String.t(),
          bpm: pos_integer() | nil
        }

  @languages [italian: "Italian", german: "German", french: "French", english: "English"]

  # Rows are {Italian, German, French, English, usual BPM}, slowest first;
  # nil where a language has no word for the tempo. The BPM is a common
  # metronome value inside the marking's usual range (sources differ by a
  # few BPM); it's only a suggestion, and the score's BPM stays free.
  @by_speed [
    {"Larghissimo", nil, nil, "As slowly as possible", 20},
    {"Grave", "Schwer", "Gravement", "Solemnly", 35},
    {"Lento assai", "Sehr langsam", "Très lent", "Very slowly", 40},
    {"Largo", "Breit", "Largement", "Broadly", 50},
    {"Lento", "Langsam", "Lent", "Slowly", 54},
    {"Adagio molto", nil, nil, "Very leisurely", 58},
    {"Larghetto", "Etwas breit", nil, "Rather broadly", 63},
    {"Adagio", "Gemächlich", nil, "Leisurely", 70},
    {"Adagietto", nil, nil, "Moderately slow", 76},
    {"Andante", "Gehend", "Allant", "At a walking pace", 84},
    {"Andante con moto", "Bewegt", nil, "Walking, with motion", 92},
    {"Andantino", nil, nil, "At an easy walking pace", 96},
    # 100 BPM: also a new score's starting tempo, with its default marking.
    {"Moderato", "Mäßig", "Modéré", "Moderately", 100},
    {nil, "Mäßig bewegt", nil, "With moderate motion", 104},
    {"Allegretto", "Etwas bewegt", "Un peu animé", "Moderately fast", 112},
    {"Allegro moderato", "Mäßig schnell", "Assez vif", "Fairly quick", 120},
    {"Allegro", "Schnell", "Vite", "Fast", 132},
    {"Allegro vivace", nil, nil, "Fast and lively", 144},
    {"Vivace", "Lebhaft", "Vif", "Lively", 156},
    {"Allegro molto", "Rasch", nil, "Briskly", 160},
    {"Allegro assai", nil, nil, "Very quick", 164},
    {"Vivacissimo", "Sehr lebhaft", "Très vif", "Very lively", 172},
    {"Allegrissimo", nil, nil, "Extremely quick", 176},
    {"Presto", "Sehr schnell", "Très vite", "Very fast", 184},
    {"Prestissimo", "Äußerst schnell", "Le plus vite possible", "As fast as possible", 208}
  ]

  # Markings that name a character or a dance as well as a speed. Those
  # that name no speed (calm, strict time, animated) suggest no BPM.
  @by_character [
    {"Tranquillo", "Ruhig", "Tranquille", "Calmly", nil},
    {"Adagio ma non troppo", nil, nil, "Slowly, but not too slowly", 66},
    {"Andante cantabile", nil, nil, "Walking, in a singing style", 80},
    {"Tempo giusto", nil, nil, "In strict time", nil},
    {"Tempo di minuetto", nil, nil, "At minuet tempo", 116},
    {"Tempo di valse", nil, nil, "At waltz tempo", 150},
    {"Tempo di marcia", nil, nil, "At march tempo", 120},
    {"Animato", "Belebt", "Animé", "Animated", nil},
    {"Allegro giusto", nil, nil, "Fast, in strict time", 132},
    {"Allegro ma non troppo", nil, nil, "Fast, but not too fast", 126},
    {"Allegro con brio", nil, nil, "Fast, with vigour", 144},
    {"Allegro con fuoco", nil, nil, "Fast, with fire", 152},
    {"Presto agitato", nil, nil, "Very fast and agitated", 184}
  ]

  @all for row <- @by_speed ++ @by_character,
           word <- Tuple.to_list(row),
           is_binary(word),
           do: word

  # The marking for the default starting tempo, 100 BPM.
  @default "Moderato"

  @doc "Every known word, in every language."
  @spec all() :: [String.t()]
  def all, do: @all

  @doc "The word a new score starts with."
  @spec default() :: String.t()
  def default, do: @default

  @doc "The marking a word belongs to, or nil for an unknown word."
  @spec find(String.t() | nil) :: t() | nil
  def find(word) do
    Enum.find(markings(), fn marking -> word in Keyword.values(words(marking)) end)
  end

  @doc "What names a marking: its first word, Italian where it has one."
  @spec key(t()) :: String.t()
  def key(%__MODULE__{} = marking), do: marking |> words() |> hd() |> elem(1)

  @doc ~S|A marking's words on one line, e.g. "Allegro · Schnell · Vite · Fast".|
  @spec label(t()) :: String.t()
  def label(%__MODULE__{} = marking), do: Enum.map_join(words(marking), " · ", &elem(&1, 1))

  @doc "A language's name, e.g. \"German\"."
  @spec language_name(language()) :: String.t()
  def language_name(language), do: Keyword.fetch!(@languages, language)

  @doc "The markings in sections, `{title, markings}`, each slowest first."
  @spec sections() :: [{String.t(), [t()]}]
  def sections do
    [
      {"By speed", Enum.map(@by_speed, &marking/1)},
      {"By character", Enum.map(@by_character, &marking/1)}
    ]
  end

  @doc """
  The word to print for `marking` when `previous` was printed before: the
  same word if it is the marking's, else the marking's word in the same
  language, else its first word. Choosing another marking so keeps the
  language the score is printed in, where the marking has a word in it.
  """
  @spec word_for(t(), String.t() | nil) :: String.t()
  def word_for(%__MODULE__{} = marking, previous) do
    # A word of this marking is its own word in its own language.
    Keyword.get(words(marking), language_of(previous)) || key(marking)
  end

  @doc "A marking's words, `{language, word}`, in the order Italian, German, French, English."
  @spec words(t()) :: [{language(), String.t()}]
  def words(%__MODULE__{} = marking) do
    for {language, _name} <- @languages,
        word = Map.fetch!(marking, language),
        do: {language, word}
  end

  defp language_of(word) do
    case find(word) do
      nil ->
        nil

      marking ->
        Enum.find_value(words(marking), fn {language, its_word} ->
          its_word == word && language
        end)
    end
  end

  defp marking({italian, german, french, english, bpm}) do
    %__MODULE__{italian: italian, german: german, french: french, english: english, bpm: bpm}
  end

  defp markings, do: Enum.flat_map(sections(), fn {_title, markings} -> markings end)
end
