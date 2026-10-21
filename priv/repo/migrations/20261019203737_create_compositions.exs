defmodule DrawMusic.Repo.Migrations.CreateCompositions do
  use Ecto.Migration

  def change do
    create table(:compositions) do
      add :name, :citext, null: false
      add :subtitle, :string
      add :composer, :string
      add :arranger, :string
      add :lyricist, :string
      add :copyright, :string
      add :notes, :text
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:compositions, [:user_id, :name])

    create table(:composition_keys) do
      add :sf, :integer, null: false
      add :mode, :string, null: false
      add :composition_id, references(:compositions, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:composition_keys, [:composition_id, :sf, :mode])
    create constraint(:composition_keys, :sf_range, check: "sf BETWEEN -7 AND 7")
    create constraint(:composition_keys, :mode_values, check: "mode IN ('major', 'minor')")

    create table(:composition_versions) do
      add :number, :integer, null: false
      add :label, :string
      add :time_num, :integer, null: false, default: 4
      add :time_den, :integer, null: false, default: 4
      add :time_symbol, :string, null: false, default: "none"
      add :tempo_bpm, :integer, null: false, default: 100
      add :tempo_text, :string
      add :pickup_ticks, :integer, null: false, default: 0
      add :instrument, :integer, null: false, default: 0
      add :score, :map, null: false, default: %{}
      add :key_id, references(:composition_keys, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:composition_versions, [:key_id, :number])
    create constraint(:composition_versions, :number_positive, check: "number > 0")

    create constraint(:composition_versions, :time_num_range, check: "time_num BETWEEN 1 AND 32")

    create constraint(:composition_versions, :time_den_power_of_two,
             check: "time_den IN (1, 2, 4, 8, 16, 32, 64)"
           )

    create constraint(:composition_versions, :time_symbol_values,
             check: "time_symbol IN ('none', 'common', 'cut')"
           )

    create constraint(:composition_versions, :tempo_range, check: "tempo_bpm BETWEEN 20 AND 400")
    create constraint(:composition_versions, :pickup_non_negative, check: "pickup_ticks >= 0")

    create constraint(:composition_versions, :instrument_range,
             check: "instrument BETWEEN 0 AND 127"
           )
  end
end
