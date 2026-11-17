defmodule DrawMusicWeb.Editor.View do
  @moduledoc """
  How the editor shows the score this session: its layout, page-style
  systems (`:page`) or one long staff (`:strip`).

  It starts from the user's preferences, and the palette switches it for the
  session only, for any reason: nothing is stored, with the user or the
  composition. When the preference itself changes (previewed, saved or put
  back in the Preferences panel), the view follows it.
  """

  alias DrawMusic.Accounts.User

  @enforce_keys [:layout]
  defstruct [:layout]

  @type layout :: :page | :strip
  @type t :: %__MODULE__{layout: layout()}

  @doc """
  The view after the user's preferences went from `old` to `new`: a changed
  layout preference is followed; otherwise the session's choice stays.
  """
  @spec follow(t(), User.t(), User.t()) :: t()
  def follow(view, %User{score_layout: same}, %User{score_layout: same}), do: view
  def follow(view, _old, %User{score_layout: layout}), do: %{view | layout: layout}

  @doc "The view an editor starts with: the user's preferred one."
  @spec from_user(User.t()) :: t()
  def from_user(%User{score_layout: layout}), do: %__MODULE__{layout: layout}
end
