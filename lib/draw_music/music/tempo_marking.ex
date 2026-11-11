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
  """

  @enforce_keys [:english]
  defstruct [:italian, :german, :french, :english]

  @type language :: :italian | :german | :french | :english

  @type t :: %__MODULE__{
          italian: String.t() | nil,
          german: String.t() | nil,
          french: String.t() | nil,
          english: String.t()
        }

  @languages [italian: "Italian", german: "German", french: "French", english: "English"]

  # Rows are {Italian, German, French, English}, slowest first; nil where a
  # language has no word for the tempo.
  @by_speed [
    {"Larghissimo", nil, nil, "As slowly as possible"},
    {"Grave", "Schwer", "Gravement", "Solemnly"},
    {"Lento assai", "Sehr langsam", "Très lent", "Very slowly"},
    {"Largo", "Breit", "Largement", "Broadly"},
    {"Lento", "Langsam", "Lent", "Slowly"},
    {"Adagio molto", nil, nil, "Very leisurely"},
    {"Larghetto", "Etwas breit", nil, "Rather broadly"},
    {"Adagio", "Gemächlich", nil, "Leisurely"},
    {"Adagietto", nil, nil, "Moderately slow"},
    {"Andante", "Gehend", "Allant", "At a walking pace"},
    {"Andante con moto", "Bewegt", nil, "Walking, with motion"},
    {"Andantino", nil, nil, "At an easy walking pace"},
    {"Moderato", "Mäßig", "Modéré", "Moderately"},
    {nil, "Mäßig bewegt", nil, "With moderate motion"},
    {"Allegretto", "Etwas bewegt", "Un peu animé", "Moderately fast"},
    {"Allegro moderato", "Mäßig schnell", "Assez vif", "Fairly quick"},
    {"Allegro", "Schnell", "Vite", "Fast"},
    {"Allegro vivace", nil, nil, "Fast and lively"},
    {"Vivace", "Lebhaft", "Vif", "Lively"},
    {"Allegro molto", "Rasch", nil, "Briskly"},
    {"Allegro assai", nil, nil, "Very quick"},
    {"Vivacissimo", "Sehr lebhaft", "Très vif", "Very lively"},
    {"Allegrissimo", nil, nil, "Extremely quick"},
    {"Presto", "Sehr schnell", "Très vite", "Very fast"},
    {"Prestissimo", "Äußerst schnell", "Le plus vite possible", "As fast as possible"}
  ]

  # Markings that name a character or a dance as well as a speed.
  @by_character [
    {"Tranquillo", "Ruhig", "Tranquille", "Calmly"},
    {"Adagio ma non troppo", nil, nil, "Slowly, but not too slowly"},
    {"Andante cantabile", nil, nil, "Walking, in a singing style"},
    {"Tempo giusto", nil, nil, "In strict time"},
    {"Tempo di minuetto", nil, nil, "At minuet tempo"},
    {"Tempo di valse", nil, nil, "At waltz tempo"},
    {"Tempo di marcia", nil, nil, "At march tempo"},
    {"Animato", "Belebt", "Animé", "Animated"},
    {"Allegro giusto", nil, nil, "Fast, in strict time"},
    {"Allegro ma non troppo", nil, nil, "Fast, but not too fast"},
    {"Allegro con brio", nil, nil, "Fast, with vigour"},
    {"Allegro con fuoco", nil, nil, "Fast, with fire"},
    {"Presto agitato", nil, nil, "Very fast and agitated"}
  ]

  @all for row <- @by_speed ++ @by_character, word <- Tuple.to_list(row), word, do: word

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

  defp marking({italian, german, french, english}) do
    %__MODULE__{italian: italian, german: german, french: french, english: english}
  end

  defp markings, do: Enum.flat_map(sections(), fn {_title, markings} -> markings end)
end
