defmodule DrawMusic.Library.Composition do
  @moduledoc """
  A named piece of music owned by a user, with its credits. Its content is
  organised as `DrawMusic.Library.Key`s, each holding numbered
  `DrawMusic.Library.Version`s. The name is unique per user, ignoring case.

  `composer` may differ from the user, e.g. for a by-ear transcription of an
  existing song; blank means the user's own work.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias DrawMusic.Accounts.Scope
  alias DrawMusic.Library.Key

  @credit_fields [:subtitle, :composer, :arranger, :lyricist, :copyright]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "compositions" do
    field :name, :string
    field :subtitle, :string
    field :composer, :string
    field :arranger, :string
    field :lyricist, :string
    field :copyright, :string
    field :notes, :string

    belongs_to :user, DrawMusic.Accounts.User
    has_many :keys, Key, preload_order: [asc: :mode, asc: :sf]

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          subtitle: String.t() | nil,
          composer: String.t() | nil,
          arranger: String.t() | nil,
          lyricist: String.t() | nil,
          copyright: String.t() | nil,
          notes: String.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          user: DrawMusic.Accounts.User.t() | Ecto.Association.NotLoaded.t(),
          keys: [Key.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc false
  @spec changeset(t(), map(), Scope.t()) :: Ecto.Changeset.t()
  def changeset(composition, attrs, %Scope{} = scope) do
    composition
    |> cast(attrs, [:name, :notes | @credit_fields])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 120)
    |> then(&Enum.reduce(@credit_fields, &1, fn f, cs -> validate_length(cs, f, max: 255) end))
    |> validate_length(:notes, max: 10_000)
    |> put_change(:user_id, scope.user.id)
    |> unique_constraint(:name,
      name: :compositions_user_id_name_index,
      message: "you already have a composition with this name"
    )
  end
end
