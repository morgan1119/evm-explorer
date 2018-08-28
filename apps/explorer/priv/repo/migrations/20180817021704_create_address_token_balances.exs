defmodule Explorer.Repo.Migrations.CreateAddressTokenBalances do
  use Ecto.Migration

  def change do
    create table(:address_token_balances) do
      add(:address_hash, references(:addresses, column: :hash, type: :bytea), null: false)
      add(:block_number, :bigint, null: false)

      add(
        :token_contract_address_hash,
        references(:tokens, column: :contract_address_hash, type: :bytea),
        null: false
      )

      add(:value, :numeric, precision: 100, default: fragment("NULL"), null: true)
      add(:value_fetched_at, :utc_datetime, default: fragment("NULL"), null: true)

      timestamps(null: false, type: :utc_datetime)
    end

    create(unique_index(:address_token_balances, ~w(address_hash token_contract_address_hash block_number)a))

    create(
      unique_index(
        :address_token_balances,
        ~w(address_hash token_contract_address_hash block_number)a,
        name: :unfetched_token_balances,
        where: "value_fetched_at IS NULL"
      )
    )
  end
end
