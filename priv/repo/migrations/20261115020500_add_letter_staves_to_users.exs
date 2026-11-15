defmodule DrawMusic.Repo.Migrations.AddLetterStavesToUsers do
  use Ecto.Migration

  # A preference (a reading aid): letter the staff lines and spaces at the
  # start of each line of music in the editor (off unless the user turns it on).
  def change do
    alter table(:users) do
      add :letter_staves, :boolean, null: false, default: false
    end
  end
end
