defmodule Explorer.Repo.Migrations.CreateInternalTransactions do
  use Ecto.Migration

  def change do
    create table(:internal_transactions) do
      add(:call_type, :string, null: true)
      add(:created_contract_code, :text, null: true)
      # null unless there is an error
      add(:error, :string, null: true)
      add(:gas, :numeric, precision: 100, null: false)
      # can be null when `error` is not `null`
      add(:gas_used, :numeric, precision: 100, null: true)
      add(:index, :integer, null: false)
      add(:init, :text)
      add(:input, :text)
      # can be null when `error` is not `null`
      add(:output, :text)
      add(:trace_address, {:array, :integer}, null: false)
      add(:type, :string, null: false)
      add(:value, :numeric, precision: 100, null: false)

      timestamps(null: false)

      # Foreign keys

      # Nullability controlled by create_has_created constraint below
      add(:created_contract_address_hash, references(:addresses, column: :hash, type: :bytea), null: true)
      add(:from_address_hash, references(:addresses, column: :hash, type: :bytea))
      add(:to_address_hash, references(:addresses, column: :hash, type: :bytea))

      add(
        :transaction_hash,
        references(:transactions, column: :hash, on_delete: :delete_all, type: :bytea),
        null: false
      )
    end

    # Constraints

    create(
      constraint(
        :internal_transactions,
        :create_has_error_or_result,
        check: """
        type != 'create' OR
        (error IS NULL AND created_contract_address_hash IS NOT NULL AND created_contract_code IS NOT NULL AND gas_used IS NOT NULL) OR
        (error IS NOT NULL AND created_contract_address_hash IS NULL AND created_contract_code IS NULL AND gas_used IS NULL)
        """
      )
    )

    create(
      constraint(
        :internal_transactions,
        :call_has_error_or_result,
        check: """
        type != 'call' OR
        (error IS NULL AND gas_used IS NOT NULL and output IS NOT NULL) OR
        (error IS NOT NULL AND gas_used IS NULL and output is NULL)
        """
      )
    )

    # Foreign Key indexes

    create(index(:internal_transactions, :from_address_hash))
    create(index(:internal_transactions, :to_address_hash))
    create(index(:internal_transactions, :transaction_hash))

    # Unique indexes

    create(index(:internal_transactions, [:transaction_hash, :index]))
  end
end
