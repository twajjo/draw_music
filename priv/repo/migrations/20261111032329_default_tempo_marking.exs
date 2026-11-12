defmodule DrawMusic.Repo.Migrations.DefaultTempoMarking do
  use Ecto.Migration

  # Every version has a tempo marking now: those without one get Moderato,
  # the marking a new score starts with.
  def up do
    execute "UPDATE composition_versions SET tempo_text = 'Moderato' WHERE tempo_text IS NULL"

    alter table(:composition_versions) do
      modify :tempo_text, :string, null: false, default: "Moderato"
    end
  end

  def down do
    alter table(:composition_versions) do
      modify :tempo_text, :string, null: true, default: nil
    end
  end
end
