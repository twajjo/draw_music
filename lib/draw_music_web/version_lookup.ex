defmodule DrawMusicWeb.VersionLookup do
  @moduledoc """
  Finds the version a `/compositions/:id/:key/v/:number` path names, among
  the signed-in user's compositions, or the blank draft the main page
  opens (`open/3`). An unknown key slug, a malformed number or someone
  else's composition all raise `Ecto.NoResultsError`, which Phoenix
  answers with a 404.
  """

  alias DrawMusic.Library
  alias DrawMusic.Library.{Composition, Key, Version}
  alias DrawMusic.Music.Score
  alias DrawMusicWeb.EditorSaving

  @draft_measures 4

  @doc "The version a path names (see the moduledoc)."
  @spec fetch!(DrawMusic.Accounts.Scope.t(), map()) :: Version.t()
  def fetch!(scope, %{"id" => id, "key" => slug, "number" => number}) do
    with {:ok, key} <- Key.from_slug(slug),
         {:ok, id} <- Ecto.UUID.cast(id),
         {number, ""} <- Integer.parse(number) do
      Library.get_version_by_number!(scope, id, key, number)
    else
      _ -> raise Ecto.NoResultsError, queryable: Version
    end
  end

  @doc """
  What the editor opens, and its page title: for `:show`, the version the
  path names, with its composition; for `:new` (the main page), a blank,
  unsaved composition: C major, 4/4, four empty measures.
  """
  @spec open(:new | :show, DrawMusic.Accounts.Scope.t(), map()) ::
          {Composition.t(), Version.t(), String.t()}
  def open(:new, _scope, _params) do
    composition = %Composition{name: EditorSaving.untitled(), keys: []}
    key = %Key{sf: 0, mode: :major, composition: composition}
    {composition, %Version{key: key, score: Score.new(@draft_measures)}, composition.name}
  end

  def open(:show, scope, params) do
    version = fetch!(scope, params)
    composition = Library.get_composition!(scope, version.key.composition.id)
    {composition, version, "#{composition.name} · #{Key.name(version.key)} v#{version.number}"}
  end
end
