defmodule DrawMusicWeb.EditorSaving do
  @moduledoc """
  What the editor needs to save a score: the name a new draft starts with,
  the composition a "Save as" starts from, and how a refused save is told
  to the user.
  """

  alias DrawMusic.Library.{Composition, Version}

  @untitled "Untitled"

  # The credits and notes a new composition copies from the current one.
  @carried [:subtitle, :composer, :arranger, :lyricist, :copyright, :notes]

  @doc "What to tell the user when a save is refused with `changeset`."
  @spec error_message(Ecto.Changeset.t()) :: String.t()
  def error_message(%Ecto.Changeset{errors: [{field, {message, _opts}} | _]}) do
    "Couldn't save: #{Phoenix.Naming.humanize(field)} #{message}"
  end

  def error_message(_changeset), do: "Couldn't save"

  @doc """
  The composition "Save as" starts from: the current one's credits and
  notes. It needs its own name, unless this is a draft that was given one.
  """
  @spec save_as_start(Composition.t(), Version.t()) :: Composition.t()
  def save_as_start(%Composition{} = composition, %Version{} = version) do
    starting =
      composition
      |> Map.take(@carried)
      |> Map.put(:name, start_name(composition, version))

    struct(Composition, starting)
  end

  @doc "The name a new, unsaved composition has."
  @spec untitled() :: String.t()
  def untitled, do: @untitled

  defp start_name(%Composition{name: @untitled}, _version), do: nil
  defp start_name(%Composition{name: name}, %Version{id: nil}), do: name
  defp start_name(_composition, _saved), do: nil
end
