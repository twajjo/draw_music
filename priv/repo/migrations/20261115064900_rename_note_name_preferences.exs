defmodule DrawMusic.Repo.Migrations.RenameNotePreferences do
  use Ecto.Migration

  # Reading-aid preferences, named for what they do: show_note_names (was
  # name_notes) names the notes being placed, moved or selected; with
  # note_names_in_edit_only off, every note is named at all times.
  def change do
    rename table(:users), :name_notes, to: :show_note_names

    alter table(:users) do
      add :note_names_in_edit_only, :boolean, null: false, default: true
    end
  end
end
