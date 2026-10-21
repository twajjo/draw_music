defmodule DrawMusic.LibraryFixtures do
  @moduledoc """
  Test helpers for creating entities via the `DrawMusic.Library` context.
  """

  alias DrawMusic.Library

  def unique_composition_name, do: "Composition #{System.unique_integer([:positive])}"

  def score_fixture(attrs \\ %{}), do: Enum.into(attrs, %{"measures" => []})

  def key_attrs(attrs \\ %{}), do: Enum.into(attrs, %{sf: 0, mode: :major})

  def version_attrs(attrs \\ %{}), do: Enum.into(attrs, %{score: score_fixture()})

  @doc """
  Creates a composition for `scope` and returns its first version, with
  `key` and `key.composition` loaded. Options: `:composition`, `:key` and
  `:version` attr maps.
  """
  def version_fixture(scope, opts \\ []) do
    composition_attrs =
      Enum.into(Keyword.get(opts, :composition, %{}), %{name: unique_composition_name()})

    {:ok, version} =
      Library.create_composition(
        scope,
        composition_attrs,
        key_attrs(Keyword.get(opts, :key, %{})),
        version_attrs(Keyword.get(opts, :version, %{}))
      )

    version
  end

  def composition_fixture(scope, opts \\ []), do: version_fixture(scope, opts).key.composition

  def import_fixture(opts \\ []) do
    %{
      composition: Keyword.get(opts, :composition, %{}),
      key: key_attrs(Keyword.get(opts, :key, %{})),
      version: version_attrs(Keyword.get(opts, :version, %{}))
    }
  end
end
