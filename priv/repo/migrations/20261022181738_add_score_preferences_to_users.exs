defmodule DrawMusic.Repo.Migrations.AddScorePreferencesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :score_layout, :string, null: false, default: "strip"
      add :score_ink_dark, :string
    end
  end
end
