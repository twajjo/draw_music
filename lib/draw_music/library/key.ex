defmodule DrawMusic.Library.Key do
  @moduledoc """
  A key a composition is kept in, e.g. G major. `sf` is the key signature as
  MIDI stores it: -7..-1 flats, 0 none, 1..7 sharps. Versions are numbered
  within their key.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias DrawMusic.Library.{Composition, Version}

  @major_tonics ~w(C♭ G♭ D♭ A♭ E♭ B♭ F C G D A E B F♯ C♯)
  @minor_tonics ~w(A♭ E♭ B♭ F C G D A E B F♯ C♯ G♯ D♯ A♯)
  @keys for sf <- -7..7, mode <- [:major, :minor], do: {sf, mode}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "composition_keys" do
    field :sf, :integer
    field :mode, Ecto.Enum, values: [:major, :minor]

    belongs_to :composition, Composition
    has_many :versions, Version, preload_order: [asc: :number]

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          sf: -7..7 | nil,
          mode: :major | :minor | nil,
          composition_id: Ecto.UUID.t() | nil,
          composition: Composition.t() | Ecto.Association.NotLoaded.t(),
          versions: [Version.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Changeset for `sf` and `mode`; `composition_id` is set by the context.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(key, attrs) do
    key
    |> cast(attrs, [:sf, :mode])
    |> validate_required([:sf, :mode])
    |> validate_number(:sf, greater_than_or_equal_to: -7, less_than_or_equal_to: 7)
    |> unique_constraint([:sf, :mode], name: :composition_keys_composition_id_sf_mode_index)
  end

  @doc """
  Human name of a key, e.g. `name(1, :major)` → `"G major"`.
  """
  @spec name(t()) :: String.t()
  @spec name(-7..7, :major | :minor) :: String.t()
  def name(%__MODULE__{sf: sf, mode: mode}), do: name(sf, mode)
  def name(sf, :major) when sf in -7..7, do: Enum.at(@major_tonics, sf + 7) <> " major"
  def name(sf, :minor) when sf in -7..7, do: Enum.at(@minor_tonics, sf + 7) <> " minor"

  @doc """
  URL slug of a key, e.g. `slug(6, :major)` → `"f-sharp-major"`.
  """
  @spec slug(t()) :: String.t()
  @spec slug(-7..7, :major | :minor) :: String.t()
  def slug(%__MODULE__{sf: sf, mode: mode}), do: slug(sf, mode)

  def slug(sf, mode) do
    sf
    |> name(mode)
    |> String.replace("♯", "-sharp")
    |> String.replace("♭", "-flat")
    |> String.replace(" ", "-")
    |> String.downcase()
  end

  @doc """
  `{:ok, {sf, mode}}` for a key slug, or `:error` for an unknown slug.
  """
  @spec from_slug(String.t()) :: {:ok, {-7..7, :major | :minor}} | :error
  def from_slug(slug) when is_binary(slug) do
    Enum.find_value(@keys, :error, fn {sf, mode} ->
      if slug(sf, mode) == slug, do: {:ok, {sf, mode}}
    end)
  end
end
