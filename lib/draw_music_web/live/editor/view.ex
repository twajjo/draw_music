defmodule DrawMusicWeb.Editor.View do
  @moduledoc """
  How the editor shows the score this session: its layout, page-style
  systems (`:page`) or one long staff (`:strip`), and its paper, black on
  white (`:white`) or the user's ink on black (`:black`).

  Both start from the user's preferences, and the palette switches them for
  the session only, for any reason: nothing is stored, with the user or the
  composition. When a preference itself changes (previewed, saved or put
  back in the Preferences panel), the view follows it.
  """

  alias DrawMusic.Accounts.User

  @enforce_keys [:layout, :paper]
  defstruct [:layout, :paper]

  @type layout :: :page | :strip
  @type paper :: :white | :black
  @type t :: %__MODULE__{layout: layout(), paper: paper()}

  @doc """
  The view after the user's preferences went from `old` to `new`: a changed
  preference is followed; otherwise the session's choice stays.
  """
  @spec follow(t(), User.t(), User.t()) :: t()
  def follow(view, %User{} = old, %User{} = new) do
    %{
      view
      | layout: follow_one(view.layout, old.score_layout, new.score_layout),
        paper: follow_one(view.paper, old.score_paper, new.score_paper)
    }
  end

  @doc "The view an editor starts with: the user's preferred one."
  @spec from_user(User.t()) :: t()
  def from_user(%User{score_layout: layout, score_paper: paper}) do
    %__MODULE__{layout: layout, paper: paper}
  end

  defp follow_one(current, same, same), do: current
  defp follow_one(_current, _old, new), do: new
end
