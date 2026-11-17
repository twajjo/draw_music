defmodule DrawMusic.Repo.Migrations.AddScorePaperToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :score_paper, :string, null: false, default: "white"
    end
  end
end
