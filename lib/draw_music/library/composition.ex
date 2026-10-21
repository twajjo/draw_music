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

  @doc false
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
