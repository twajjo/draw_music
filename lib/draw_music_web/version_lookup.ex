defmodule DrawMusicWeb.VersionLookup do
  @moduledoc """
  Finds the version a `/compositions/:id/:key/v/:number` path names, among
  the signed-in user's compositions. An unknown key slug, a malformed
  number or someone else's composition all raise `Ecto.NoResultsError`,
  which Phoenix answers with a 404.
  """

  alias DrawMusic.Library
  alias DrawMusic.Library.{Key, Version}

  def fetch!(scope, %{"id" => id, "key" => slug, "number" => number}) do
    with {:ok, key} <- Key.from_slug(slug),
         {:ok, id} <- Ecto.UUID.cast(id),
         {number, ""} <- Integer.parse(number) do
      Library.get_version_by_number!(scope, id, key, number)
    else
      _ -> raise Ecto.NoResultsError, queryable: Version
    end
  end
end
