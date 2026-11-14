defmodule DrawMusic.Repo.Migrations.AddNameNotesToUsers do
  use Ecto.Migration

  # A preference: name the note being placed or dragged (on unless the user
  # turns it off).
  def change do
    alter table(:users) do
      add :name_notes, :boolean, null: false, default: true
    end
  end
end
