defmodule DrawMusic.Repo.Migrations.WidenTempoRange do
  use Ecto.Migration

  # Imported music slows below 20 BPM (fermata-like holds); tempo changes
  # in the score share the starting tempo's range.
  def up do
    drop constraint(:composition_versions, :tempo_range)
    create constraint(:composition_versions, :tempo_range, check: "tempo_bpm BETWEEN 5 AND 400")
  end

  def down do
    execute "UPDATE composition_versions SET tempo_bpm = 20 WHERE tempo_bpm < 20"
    drop constraint(:composition_versions, :tempo_range)
    create constraint(:composition_versions, :tempo_range, check: "tempo_bpm BETWEEN 20 AND 400")
  end
end
