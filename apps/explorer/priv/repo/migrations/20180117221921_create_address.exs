defmodule Explorer.Repo.Migrations.CreateAddress do
  use Ecto.Migration

  def change do
    create table(:addresses, primary_key: false) do
      add(:balance, :numeric, precision: 100)
      add(:balance_updated_at, :utc_datetime)
      add(:hash, :bytea, null: false, primary_key: true)

      timestamps(null: false)
    end
  end
end
