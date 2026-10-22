defmodule DrawMusic.Library do
  @moduledoc """
  The Library context: a user's compositions, the keys each is kept in, and
  the numbered versions within each key.

      Composition ─┬─ Key (G major) ─┬─ Version 1
                   │                 └─ Version 2
                   └─ Key (D major) ─── Version 1

  Every function takes the caller's `%Scope{}`; records are only ever read or
  written for `scope.user`. Functions that produce a version return it with
  `key` and `key.composition` loaded.
  """

  import Ecto.Query, warn: false

  alias DrawMusic.Accounts.Scope
  alias DrawMusic.Library.{Composition, Import, Key, Version}
  alias DrawMusic.Repo

  ## Compositions

  @doc """
  Lists the user's compositions by name, with keys and version summaries
  (no scores) preloaded.
  """
  @spec list_compositions(Scope.t()) :: [Composition.t()]
  def list_compositions(%Scope{} = scope) do
    Composition
    |> where(user_id: ^scope.user.id)
    |> order_by(asc: :name)
    |> preload(keys: [versions: ^version_summaries()])
    |> Repo.all()
  end

  @doc """
  Gets one of the user's compositions with keys and version summaries
  preloaded. Raises `Ecto.NoResultsError` if it does not exist or belongs to
  someone else.
  """
  @spec get_composition!(Scope.t(), Ecto.UUID.t()) :: Composition.t()
  def get_composition!(%Scope{} = scope, id) do
    Composition
    |> where(user_id: ^scope.user.id, id: ^id)
    |> preload(keys: [versions: ^version_summaries()])
    |> Repo.one!()
  end

  @doc """
  Finds the user's composition with `name`, ignoring case. Returns `nil` if none.
  """
  @spec get_composition_by_name(Scope.t(), String.t()) :: Composition.t() | nil
  def get_composition_by_name(%Scope{} = scope, name) when is_binary(name) do
    Repo.get_by(Composition, user_id: scope.user.id, name: String.trim(name))
  end

  @doc """
  Creates a composition (`composition_attrs`: name and credits) with one key
  (`key_attrs`: `sf`, `mode`) holding version 1 (`version_attrs`).
  """
  @spec create_composition(Scope.t(), map(), map(), map()) ::
          {:ok, Version.t()} | {:error, Ecto.Changeset.t()}
  def create_composition(%Scope{} = scope, composition_attrs, key_attrs, version_attrs) do
    Repo.transact(fn ->
      with {:ok, composition} <-
             %Composition{}
             |> Composition.changeset(composition_attrs, scope)
             |> Repo.insert(),
           {:ok, key} <- get_or_create_key(composition, key_attrs) do
        insert_version(key, 1, version_attrs)
      end
    end)
  end

  @doc """
  Returns a changeset for tracking composition changes in forms.
  """
  @spec change_composition(Scope.t(), Composition.t()) :: Ecto.Changeset.t()
  @spec change_composition(Scope.t(), Composition.t(), map()) :: Ecto.Changeset.t()
  def change_composition(%Scope{} = scope, %Composition{} = composition, attrs \\ %{}) do
    Composition.changeset(composition, attrs, scope)
  end

  @doc """
  Updates a composition's name, credits and notes.
  """
  @spec update_composition(Scope.t(), Composition.t(), map()) ::
          {:ok, Composition.t()} | {:error, Ecto.Changeset.t()}
  def update_composition(%Scope{} = scope, %Composition{} = composition, attrs) do
    true = owner?(scope, composition)

    composition
    |> Composition.changeset(attrs, scope)
    |> Repo.update()
  end

  @doc """
  Deletes a composition with all of its keys and versions.
  """
  @spec delete_composition(Scope.t(), Composition.t()) ::
          {:ok, Composition.t()} | {:error, Ecto.Changeset.t()}
  def delete_composition(%Scope{} = scope, %Composition{} = composition) do
    true = owner?(scope, composition)
    Repo.delete(composition)
  end

  ## Keys

  @doc """
  Deletes a key and its versions. A composition's last key cannot be deleted;
  delete the composition instead.
  """
  @spec delete_key(Scope.t(), Key.t()) ::
          {:ok, Key.t()} | {:error, :last_key | Ecto.Changeset.t()}
  def delete_key(%Scope{} = scope, %Key{composition: %Composition{} = composition} = key) do
    true = owner?(scope, composition)

    Repo.transact(fn ->
      lock_composition!(composition.id)

      if key_count(composition.id) > 1 do
        Repo.delete(key)
      else
        {:error, :last_key}
      end
    end)
  end

  ## Versions

  @doc """
  Gets one of the user's versions by id, with `key` and `key.composition`
  loaded. Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_version!(Scope.t(), Ecto.UUID.t()) :: Version.t()
  def get_version!(%Scope{} = scope, id) do
    scope
    |> owned_versions()
    |> where([v], v.id == ^id)
    |> Repo.one!()
  end

  @doc """
  Gets the highest-numbered version in one of the user's keys.
  """
  @spec get_latest_version!(Scope.t(), Ecto.UUID.t()) :: Version.t()
  def get_latest_version!(%Scope{} = scope, key_id) do
    scope
    |> owned_versions()
    |> where([v], v.key_id == ^key_id)
    |> order_by(desc: :number)
    |> limit(1)
    |> Repo.one!()
  end

  @doc """
  Gets version `number` of one of the user's compositions in the key
  `{sf, mode}`, with `key` and `key.composition` loaded. Raises
  `Ecto.NoResultsError` if not found.
  """
  @spec get_version_by_number!(Scope.t(), Ecto.UUID.t(), {-7..7, :major | :minor}, pos_integer()) ::
          Version.t()
  def get_version_by_number!(%Scope{} = scope, composition_id, {sf, mode}, number) do
    scope
    |> owned_versions()
    |> where([v, k, c], c.id == ^composition_id and k.sf == ^sf and k.mode == ^mode)
    |> where([v], v.number == ^number)
    |> Repo.one!()
  end

  @doc """
  Returns a changeset for tracking version changes in forms.
  """
  @spec change_version(Version.t()) :: Ecto.Changeset.t()
  @spec change_version(Version.t(), map()) :: Ecto.Changeset.t()
  def change_version(%Version{} = version, attrs \\ %{}), do: Version.changeset(version, attrs)

  @doc """
  Save: overwrites an existing version's content.
  """
  @spec save_version(Scope.t(), Version.t(), map()) ::
          {:ok, Version.t()} | {:error, Ecto.Changeset.t()}
  def save_version(
        %Scope{} = scope,
        %Version{key: %Key{composition: %Composition{}}} = version,
        attrs
      ) do
    true = owner?(scope, version.key.composition)

    version
    |> Version.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Save as new version: stores `attrs` under the key's next version number.
  """
  @spec save_new_version(Scope.t(), Key.t(), map()) ::
          {:ok, Version.t()} | {:error, Ecto.Changeset.t()}
  def save_new_version(
        %Scope{} = scope,
        %Key{composition: %Composition{} = composition} = key,
        attrs
      ) do
    true = owner?(scope, composition)

    Repo.transact(fn ->
      lock_composition!(composition.id)
      insert_version(key, next_number(key.id), attrs)
    end)
  end

  @doc """
  Stores `version_attrs` as the next version under `key_attrs` (`sf`, `mode`)
  in an existing composition, creating that key if the composition does not
  have it yet. Used when transposing into another key.
  """
  @spec save_in_key(Scope.t(), Composition.t(), map(), map()) ::
          {:ok, Version.t()} | {:error, Ecto.Changeset.t()}
  def save_in_key(%Scope{} = scope, %Composition{} = composition, key_attrs, version_attrs) do
    true = owner?(scope, composition)

    Repo.transact(fn ->
      locked = lock_composition!(composition.id)

      with {:ok, key} <- get_or_create_key(locked, key_attrs) do
        insert_version(key, next_number(key.id), version_attrs)
      end
    end)
  end

  @doc """
  Save as new composition: same as `create_composition/4`.
  """
  @spec save_as_new_composition(Scope.t(), map(), map(), map()) ::
          {:ok, Version.t()} | {:error, Ecto.Changeset.t()}
  def save_as_new_composition(%Scope{} = scope, composition_attrs, key_attrs, version_attrs),
    do: create_composition(scope, composition_attrs, key_attrs, version_attrs)

  @doc """
  Deletes one version. If it is the only version in its key, the key goes
  too, unless that is the composition's only key: the composition's last
  version cannot be deleted (`{:error, :last_version}`).
  """
  @spec delete_version(Scope.t(), Version.t()) ::
          {:ok, Version.t()} | {:error, :last_version | Ecto.Changeset.t()}
  def delete_version(%Scope{} = scope, %Version{key: %Key{composition: %Composition{}}} = version) do
    composition = version.key.composition
    true = owner?(scope, composition)

    Repo.transact(fn ->
      lock_composition!(composition.id)

      cond do
        version_count(version.key_id) > 1 -> Repo.delete(version)
        key_count(composition.id) > 1 -> delete_key_of(version)
        true -> {:error, :last_version}
      end
    end)
  end

  defp delete_key_of(%Version{} = version) do
    with {:ok, _key} <- Repo.delete(version.key), do: {:ok, version}
  end

  ## Import

  @doc """
  Stores an imported piece (a `DrawMusic.Library.Import`, e.g. from
  `DrawMusic.MidiCodec.import/2`) under `name`. The key comes from the
  file's key signature. A name collision is resolved by `resolution`:

    * `:new` - create a new composition; `{:error, :name_taken}` if the name exists
    * `:replace` - in the existing composition, delete every version under the
      import's key and store the import as that key's version 1 (other keys
      are untouched)
    * `:new_version` - add the import as the next version under its key in the
      existing composition, creating the key if needed

  `:replace` and `:new_version` return `{:error, :not_found}` when no
  composition has that name.
  """
  @spec import_score(Scope.t(), String.t(), Import.t(), :new | :replace | :new_version) ::
          {:ok, Version.t()} | {:error, :name_taken | :not_found | Ecto.Changeset.t()}
  def import_score(scope, name, import, resolution)

  def import_score(%Scope{} = scope, name, %Import{} = import, :new) do
    case get_composition_by_name(scope, name) do
      nil ->
        composition_attrs = Map.put(import.composition, :name, name)
        create_composition(scope, composition_attrs, import.key, import.version)

      %Composition{} ->
        {:error, :name_taken}
    end
  end

  def import_score(%Scope{} = scope, name, import, :replace) do
    with {:ok, composition} <- fetch_by_name(scope, name) do
      Repo.transact(fn -> replace_key_versions(composition, import) end)
    end
  end

  def import_score(%Scope{} = scope, name, import, :new_version) do
    with {:ok, composition} <- fetch_by_name(scope, name) do
      save_in_key(scope, composition, import.key, import.version)
    end
  end

  ## Helpers

  defp replace_key_versions(%Composition{} = composition, import) do
    locked = lock_composition!(composition.id)

    with {:ok, key} <- get_or_create_key(locked, import.key) do
      Repo.delete_all(where(Version, key_id: ^key.id))
      insert_version(key, 1, import.version)
    end
  end

  defp fetch_by_name(scope, name) do
    case get_composition_by_name(scope, name) do
      nil -> {:error, :not_found}
      composition -> {:ok, composition}
    end
  end

  # Callers hold the composition lock (or just inserted the composition).
  defp get_or_create_key(%Composition{} = composition, key_attrs) do
    changeset = Key.changeset(%Key{composition_id: composition.id}, key_attrs)

    existing =
      changeset.valid? &&
        Repo.get_by(Key,
          composition_id: composition.id,
          sf: Ecto.Changeset.get_field(changeset, :sf),
          mode: Ecto.Changeset.get_field(changeset, :mode)
        )

    case existing do
      %Key{} = key -> {:ok, %{key | composition: composition}}
      _ -> with {:ok, key} <- Repo.insert(changeset), do: {:ok, %{key | composition: composition}}
    end
  end

  defp insert_version(%Key{} = key, number, attrs) do
    with {:ok, version} <-
           %Version{key_id: key.id, number: number}
           |> Version.changeset(attrs)
           |> Repo.insert() do
      {:ok, %{version | key: key}}
    end
  end

  defp owned_versions(%Scope{} = scope) do
    Version
    |> join(:inner, [v], k in assoc(v, :key))
    |> join(:inner, [_v, k], c in assoc(k, :composition))
    |> where([_v, _k, c], c.user_id == ^scope.user.id)
    |> preload([_v, k, c], key: {k, composition: c})
  end

  defp lock_composition!(id) do
    Composition
    |> where(id: ^id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp next_number(key_id) do
    Version
    |> where(key_id: ^key_id)
    |> select([v], coalesce(max(v.number), 0))
    |> Repo.one()
    |> Kernel.+(1)
  end

  defp version_count(key_id), do: Version |> where(key_id: ^key_id) |> Repo.aggregate(:count)

  defp key_count(composition_id),
    do: Key |> where(composition_id: ^composition_id) |> Repo.aggregate(:count)

  defp version_summaries do
    from v in Version,
      order_by: v.number,
      select:
        struct(v, [
          :id,
          :number,
          :key_id,
          :label,
          :time_num,
          :time_den,
          :time_symbol,
          :tempo_bpm,
          :inserted_at,
          :updated_at
        ])
  end

  defp owner?(%Scope{user: user}, %Composition{user_id: user_id}), do: user.id == user_id
end
