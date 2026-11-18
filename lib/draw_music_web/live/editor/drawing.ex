defmodule DrawMusicWeb.Editor.Drawing do
  @moduledoc """
  The score as `DrawMusicWeb.EditorLive` last laid it out (`draw/3`),
  rebuilt together after each change:

    * `engraved`: the `DrawMusic.Engraving.Engraved` layout;
    * `pieces`: it drawn, with the user's reading aids
      (`DrawMusicWeb.ScoreSvg.pieces/2`);
    * `geometry_json`: where things are, for the score's hook
      (`DrawMusicWeb.EditorGeometry.encode/2`, as JSON);
    * `loading?`: whether it is still the placeholder shown until the score
      is engraved;
    * `key_suggestion`: better keys for the score
      (`DrawMusic.Music.KeySuggestion`), for the Suggest key button.
  """

  alias DrawMusic.Accounts.User
  alias DrawMusic.Engraving.{Engraved, Layout}
  alias DrawMusic.Music.{Context, KeySuggestion, Score}
  alias DrawMusicWeb.Editor.View
  alias DrawMusicWeb.{EditorGeometry, ReadingAids, ScoreComponents, ScoreSvg}

  # The preferences drawn into the pieces.
  @reading_aids [:show_note_names, :note_names_in_edit_only, :letter_staves]

  @enforce_keys [:engraved, :pieces, :geometry_json, :loading?, :key_suggestion]
  defstruct [:engraved, :pieces, :geometry_json, :loading?, :key_suggestion]

  @type t :: %__MODULE__{
          engraved: Engraved.t(),
          pieces: list(),
          geometry_json: String.t(),
          loading?: boolean(),
          key_suggestion: KeySuggestion.t()
        }

  @doc """
  What a drawing depends on besides the score: the layout and the reading
  aids. When it changes from one to the other, the score is laid out again
  if the layout differs, else only its pieces are drawn again (`repaint/3`).
  The paper and ink are CSS, so they're not in it.
  """
  @spec basis(User.t(), View.t()) :: {View.layout(), map()}
  def basis(%User{} = user, %View{layout: layout}), do: {layout, Map.take(user, @reading_aids)}

  @doc """
  `score` laid out and drawn for the editor, in `view`'s layout with
  `user`'s reading aids, the opening tempo `marking` over it. `loading?`
  marks the placeholder shown until the real score is engraved.
  """
  @spec draw(Score.t(), Context.t(), keyword()) :: t()
  def draw(%Score{} = score, %Context{} = ctx, opts) do
    %View{} = view = Keyword.fetch!(opts, :view)
    width = ScoreComponents.layout_width(view.layout)
    engraved = Layout.layout(score, ctx, width: width, marking: Keyword.get(opts, :marking))

    # The score goes to the browser in pieces, each one finished piece of
    # SVG, not as a LiveView diff of every glyph and line: a long piece has
    # tens of thousands, and building those one by one in the browser takes
    # long enough for the connection to time out. Parsed whole, it's quick,
    # and only the pieces an edit changes are sent again.
    %__MODULE__{
      engraved: engraved,
      pieces: pieces(engraved, Keyword.fetch!(opts, :user), view),
      geometry_json: Jason.encode!(EditorGeometry.encode(engraved, ctx)),
      loading?: Keyword.get(opts, :loading?, false),
      key_suggestion: KeySuggestion.suggest(score, {ctx.sf, ctx.mode})
    }
  end

  @doc "The same layout drawn again, for new reading aids."
  @spec repaint(t(), User.t(), View.t()) :: t()
  def repaint(%__MODULE__{} = drawing, %User{} = user, %View{} = view) do
    %{drawing | pieces: pieces(drawing.engraved, user, view)}
  end

  # The engraving drawn, with the user's reading aids (only here: the export
  # draws the engraving without them).
  defp pieces(engraved, user, %View{layout: layout}) do
    ScoreSvg.pieces(ReadingAids.add(engraved, user), layout)
  end
end
