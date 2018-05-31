defmodule Explorer.Repo.Migrations.CreateAddress do
  use Ecto.Migration

  def change do
    create table(:addresses, primary_key: false) do
      add(:fetched_balance, :numeric, precision: 100)
      add(:balance_fetched_at, :utc_datetime)
      add(:hash, :bytea, null: false, primary_key: true)
      add(:contract_code, :bytea, null: true)

      timestamps(null: false, type: :utc_datetime)
    end
  end
end
