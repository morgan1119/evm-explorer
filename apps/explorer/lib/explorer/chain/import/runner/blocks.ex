defmodule Explorer.Chain.Import.Runner.Blocks do
  @moduledoc """
  Bulk imports `t:Explorer.Chain.Block.t/0`.
  """

  require Ecto.Query

  import Ecto.Query, only: [from: 2, lock: 2, order_by: 2, subquery: 1]

  alias Ecto.{Changeset, Multi, Repo}
  alias Explorer.Chain.{Address, Block, Hash, Import, InternalTransaction, Log, TokenTransfer, Transaction}
  alias Explorer.Chain.Block.Reward
  alias Explorer.Chain.Import.Runner
  alias Explorer.Chain.Import.Runner.Address.CurrentTokenBalances
  alias Explorer.Chain.Import.Runner.Tokens

  @behaviour Runner

  # milliseconds
  @timeout 60_000

  @type imported :: [Block.t()]

  @impl Runner
  def ecto_schema_module, do: Block

  @impl Runner
  def option_key, do: :blocks

  @impl Runner
  def imported_table_row do
    %{
      value_type: "[#{ecto_schema_module()}.t()]",
      value_description: "List of `t:#{ecto_schema_module()}.t/0`s"
    }
  end

  @impl Runner
  def run(multi, changes_list, %{timestamps: timestamps} = options) do
    insert_options =
      options
      |> Map.get(option_key(), %{})
      |> Map.take(~w(on_conflict timeout)a)
      |> Map.put_new(:timeout, @timeout)
      |> Map.put(:timestamps, timestamps)

    ordered_consensus_block_numbers = ordered_consensus_block_numbers(changes_list)
    where_invalid_neighbour = where_invalid_neighbour(changes_list)
    where_forked = where_forked(changes_list)

    multi
    |> Multi.run(:derive_transaction_forks, fn repo, _ ->
      derive_transaction_forks(%{
        repo: repo,
        timeout: options[Runner.Transaction.Forks.option_key()][:timeout] || Runner.Transaction.Forks.timeout(),
        timestamps: timestamps,
        where_forked: where_forked
      })
    end)
    |> Multi.run(:lose_consensus, fn repo, _ ->
      lose_consensus(repo, ordered_consensus_block_numbers, insert_options)
    end)
    |> Multi.run(:lose_invalid_neighbour_consensus, fn repo, _ ->
      lose_invalid_neighbour_consensus(repo, where_invalid_neighbour, insert_options)
    end)
    |> Multi.run(:remove_nonconsensus_data, fn repo,
                                               %{
                                                 lose_consensus: lost_consensus_blocks,
                                                 lose_invalid_neighbour_consensus: lost_consensus_neighbours
                                               } ->
      nonconsensus_block_numbers =
        (lost_consensus_blocks ++ lost_consensus_neighbours)
        |> Enum.map(fn %{number: number} ->
          number
        end)
        |> Enum.sort()
        |> Enum.dedup()

      remove_nonconsensus_data(
        repo,
        nonconsensus_block_numbers,
        insert_options
      )
    end)
    # MUST be after `:derive_transaction_forks`, which depends on values in `transactions` table
    |> Multi.run(:fork_transactions, fn repo, _ ->
      fork_transactions(%{
        repo: repo,
        timeout: options[Runner.Transactions.option_key()][:timeout] || Runner.Transactions.timeout(),
        timestamps: timestamps,
        where_forked: where_forked
      })
    end)
    |> Multi.run(:delete_address_token_balances, fn repo, _ ->
      delete_address_token_balances(repo, ordered_consensus_block_numbers, insert_options)
    end)
    |> Multi.run(:delete_address_current_token_balances, fn repo, _ ->
      delete_address_current_token_balances(repo, ordered_consensus_block_numbers, insert_options)
    end)
    |> Multi.run(:derive_address_current_token_balances, fn repo,
                                                            %{
                                                              delete_address_current_token_balances:
                                                                deleted_address_current_token_balances
                                                            } ->
      derive_address_current_token_balances(repo, deleted_address_current_token_balances, insert_options)
    end)
    |> Multi.run(:blocks_update_token_holder_counts, fn repo,
                                                        %{
                                                          delete_address_current_token_balances: deleted,
                                                          derive_address_current_token_balances: inserted
                                                        } ->
      deltas = CurrentTokenBalances.token_holder_count_deltas(%{deleted: deleted, inserted: inserted})
      Tokens.update_holder_counts_with_deltas(repo, deltas, insert_options)
    end)
    |> Multi.run(:delete_rewards, fn repo, _ ->
      delete_rewards(repo, changes_list, insert_options)
    end)
    |> Multi.run(:blocks, fn repo, _ ->
      insert(repo, changes_list, insert_options)
    end)
    |> Multi.run(:uncle_fetched_block_second_degree_relations, fn repo, %{blocks: blocks} when is_list(blocks) ->
      update_block_second_degree_relations(
        repo,
        blocks,
        %{
          timeout:
            options[Runner.Block.SecondDegreeRelations.option_key()][:timeout] ||
              Runner.Block.SecondDegreeRelations.timeout(),
          timestamps: timestamps
        }
      )
    end)
    |> Multi.run(:internal_transaction_transaction_block_number, fn repo, %{blocks: blocks} when is_list(blocks) ->
      update_internal_transaction_block_number(repo, blocks)
    end)
  end

  @impl Runner
  def timeout, do: @timeout

  defp derive_transaction_forks(%{
         repo: repo,
         timeout: timeout,
         timestamps: %{inserted_at: inserted_at, updated_at: updated_at},
         where_forked: where_forked
       }) do
    multi =
      Multi.new()
      |> Multi.run(:get_forks, fn repo, _ ->
        query =
          from(transaction in where_forked,
            select: %{
              uncle_hash: transaction.block_hash,
              index: transaction.index,
              hash: transaction.hash,
              inserted_at: type(^inserted_at, transaction.inserted_at),
              updated_at: type(^updated_at, transaction.updated_at)
            }
          )

        transactions = repo.all(query)
        {:ok, transactions}
      end)
      |> Multi.run(:insert_transaction_forks, fn repo, %{get_forks: transactions} ->
        # Enforce Fork ShareLocks order (see docs: sharelocks.md)
        ordered_forks = Enum.sort_by(transactions, &{&1.uncle_hash, &1.index})

        {_total, result} =
          repo.insert_all(
            Transaction.Fork,
            ordered_forks,
            conflict_target: [:uncle_hash, :index],
            on_conflict:
              from(
                transaction_fork in Transaction.Fork,
                update: [set: [hash: fragment("EXCLUDED.hash")]],
                where: fragment("EXCLUDED.hash <> ?", transaction_fork.hash)
              ),
            returning: [:uncle_hash, :hash]
          )

        {:ok, result}
      end)

    with {:ok, %{insert_transaction_forks: rows}} <- repo.transaction(multi, timeout: timeout) do
      derived_transaction_forks = Enum.map(rows, &Map.take(&1, [:uncle_hash, :hash]))

      {:ok, derived_transaction_forks}
    end
  end

  defp fork_transactions(%{
         repo: repo,
         timeout: timeout,
         timestamps: %{updated_at: updated_at},
         where_forked: where_forked
       }) do
    query =
      where_forked
      # Enforce Transaction ShareLocks order (see docs: sharelocks.md)
      |> order_by(asc: :hash)
      |> lock("FOR UPDATE")

    update_query =
      from(t in Transaction,
        join: s in subquery(query),
        on: t.hash == s.hash,
        update: [
          set: [
            block_hash: nil,
            block_number: nil,
            gas_used: nil,
            cumulative_gas_used: nil,
            index: nil,
            internal_transactions_indexed_at: nil,
            status: nil,
            error: nil,
            updated_at: ^updated_at
          ]
        ],
        select: t.hash
      )

    try do
      {_, result} = repo.update_all(update_query, [], timeout: timeout)

      {:ok, result}
    rescue
      postgrex_error in Postgrex.Error ->
        {:error, %{exception: postgrex_error}}
    end
  end

  @spec insert(Repo.t(), [map()], %{
          optional(:on_conflict) => Runner.on_conflict(),
          required(:timeout) => timeout,
          required(:timestamps) => Import.timestamps()
        }) :: {:ok, [Block.t()]} | {:error, [Changeset.t()]}
  defp insert(repo, changes_list, %{timeout: timeout, timestamps: timestamps} = options) when is_list(changes_list) do
    on_conflict = Map.get_lazy(options, :on_conflict, &default_on_conflict/0)

    # Enforce Block ShareLocks order (see docs: sharelocks.md)
    ordered_changes_list = Enum.sort_by(changes_list, & &1.hash)

    Import.insert_changes_list(
      repo,
      ordered_changes_list,
      conflict_target: :hash,
      on_conflict: on_conflict,
      for: Block,
      returning: true,
      timeout: timeout,
      timestamps: timestamps
    )
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp default_on_conflict do
    from(
      block in Block,
      update: [
        set: [
          consensus: fragment("EXCLUDED.consensus"),
          difficulty: fragment("EXCLUDED.difficulty"),
          gas_limit: fragment("EXCLUDED.gas_limit"),
          gas_used: fragment("EXCLUDED.gas_used"),
          internal_transactions_indexed_at: fragment("EXCLUDED.internal_transactions_indexed_at"),
          miner_hash: fragment("EXCLUDED.miner_hash"),
          nonce: fragment("EXCLUDED.nonce"),
          number: fragment("EXCLUDED.number"),
          parent_hash: fragment("EXCLUDED.parent_hash"),
          size: fragment("EXCLUDED.size"),
          timestamp: fragment("EXCLUDED.timestamp"),
          total_difficulty: fragment("EXCLUDED.total_difficulty"),
          # Don't update `hash` as it is used for the conflict target
          inserted_at: fragment("LEAST(?, EXCLUDED.inserted_at)", block.inserted_at),
          updated_at: fragment("GREATEST(?, EXCLUDED.updated_at)", block.updated_at)
        ]
      ],
      where:
        fragment("EXCLUDED.consensus <> ?", block.consensus) or fragment("EXCLUDED.difficulty <> ?", block.difficulty) or
          fragment("EXCLUDED.gas_limit <> ?", block.gas_limit) or fragment("EXCLUDED.gas_used <> ?", block.gas_used) or
          fragment("EXCLUDED.miner_hash <> ?", block.miner_hash) or fragment("EXCLUDED.nonce <> ?", block.nonce) or
          fragment("EXCLUDED.number <> ?", block.number) or fragment("EXCLUDED.parent_hash <> ?", block.parent_hash) or
          fragment("EXCLUDED.size <> ?", block.size) or fragment("EXCLUDED.timestamp <> ?", block.timestamp) or
          fragment("EXCLUDED.total_difficulty <> ?", block.total_difficulty) or
          fragment("EXCLUDED.internal_transactions_indexed_at <> ?", block.internal_transactions_indexed_at)
    )
  end

  defp ordered_consensus_block_numbers(blocks_changes) when is_list(blocks_changes) do
    blocks_changes
    |> Enum.reduce(MapSet.new(), fn
      %{consensus: true, number: number}, acc ->
        MapSet.put(acc, number)

      %{consensus: false}, acc ->
        acc
    end)
    |> Enum.sort()
  end

  defp lose_consensus(_, [], _), do: {:ok, []}

  defp lose_consensus(repo, ordered_consensus_block_number, %{timeout: timeout, timestamps: %{updated_at: updated_at}})
       when is_list(ordered_consensus_block_number) do
    query =
      from(
        block in Block,
        where: block.number in ^ordered_consensus_block_number,
        # Enforce Block ShareLocks order (see docs: sharelocks.md)
        order_by: [asc: block.hash],
        lock: "FOR UPDATE"
      )

    try do
      {_, result} =
        repo.update_all(
          from(b in Block, join: s in subquery(query), on: b.hash == s.hash, select: [:hash, :number]),
          [set: [consensus: false, updated_at: updated_at]],
          timeout: timeout
        )

      {:ok, result}
    rescue
      postgrex_error in Postgrex.Error ->
        {:error, %{exception: postgrex_error, consensus_block_numbers: ordered_consensus_block_number}}
    end
  end

  defp lose_invalid_neighbour_consensus(repo, where_invalid_neighbour, %{
         timeout: timeout,
         timestamps: %{updated_at: updated_at}
       }) do
    query =
      from(
        block in where_invalid_neighbour,
        # Enforce Block ShareLocks order (see docs: sharelocks.md)
        order_by: [asc: block.hash],
        lock: "FOR UPDATE"
      )

    try do
      {_, result} =
        repo.update_all(
          from(b in Block, join: s in subquery(query), on: b.hash == s.hash, select: [:hash, :number]),
          [set: [consensus: false, updated_at: updated_at]],
          timeout: timeout
        )

      {:ok, result}
    rescue
      postgrex_error in Postgrex.Error ->
        {:error, %{exception: postgrex_error, where_invalid_neighbour: where_invalid_neighbour}}
    end
  end

  defp remove_nonconsensus_data(
         repo,
         nonconsensus_block_numbers,
         insert_options
       ) do
    with {:ok, deleted_token_transfers} <-
           remove_nonconsensus_token_transfers(repo, nonconsensus_block_numbers, insert_options),
         {:ok, deleted_logs} <- remove_nonconsensus_logs(repo, nonconsensus_block_numbers, insert_options),
         {:ok, deleted_internal_transactions} <-
           remove_nonconsensus_internal_transactions(repo, nonconsensus_block_numbers, insert_options) do
      {:ok,
       %{
         token_transfers: deleted_token_transfers,
         logs: deleted_logs,
         internal_transactions: deleted_internal_transactions
       }}
    end
  end

  defp remove_nonconsensus_token_transfers(repo, nonconsensus_block_numbers, %{timeout: timeout}) do
    ordered_token_transfers =
      from(token_transfer in TokenTransfer,
        where: token_transfer.block_number in ^nonconsensus_block_numbers,
        select: map(token_transfer, [:transaction_hash, :log_index]),
        # Enforce TokenTransfer ShareLocks order (see docs: sharelocks.md)
        order_by: [
          token_transfer.transaction_hash,
          token_transfer.log_index
        ],
        lock: "FOR UPDATE"
      )

    query =
      from(token_transfer in TokenTransfer,
        select: map(token_transfer, [:transaction_hash, :log_index]),
        inner_join: ordered_token_transfer in subquery(ordered_token_transfers),
        on:
          ordered_token_transfer.transaction_hash ==
            token_transfer.transaction_hash and
            ordered_token_transfer.log_index == token_transfer.log_index
      )

    try do
      {_count, deleted_token_transfers} = repo.delete_all(query, timeout: timeout)

      {:ok, deleted_token_transfers}
    rescue
      postgrex_error in Postgrex.Error ->
        {:error, %{exception: postgrex_error, block_numbers: nonconsensus_block_numbers}}
    end
  end

  defp remove_nonconsensus_internal_transactions(repo, nonconsensus_block_numbers, %{timeout: timeout}) do
    transaction_query =
      from(transaction in Transaction,
        where: transaction.block_number in ^nonconsensus_block_numbers,
        select: map(transaction, [:hash]),
        order_by: transaction.hash
      )

    ordered_internal_transactions =
      from(internal_transaction in InternalTransaction,
        inner_join: transaction in subquery(transaction_query),
        on: internal_transaction.transaction_hash == transaction.hash,
        select: map(internal_transaction, [:transaction_hash, :index]),
        # Enforce InternalTransaction ShareLocks order (see docs: sharelocks.md)
        order_by: [
          internal_transaction.transaction_hash,
          internal_transaction.index
        ],
        lock: "FOR UPDATE OF i0"
      )

    query =
      from(internal_transaction in InternalTransaction,
        select: map(internal_transaction, [:transaction_hash, :index]),
        inner_join: ordered_internal_transaction in subquery(ordered_internal_transactions),
        on:
          ordered_internal_transaction.transaction_hash == internal_transaction.transaction_hash and
            ordered_internal_transaction.index == internal_transaction.index
      )

    try do
      {_count, deleted_internal_transactions} = repo.delete_all(query, timeout: timeout)

      {:ok, deleted_internal_transactions}
    rescue
      postgrex_error in Postgrex.Error ->
        {:error, %{exception: postgrex_error, block_numbers: nonconsensus_block_numbers}}
    end
  end

  defp remove_nonconsensus_logs(repo, nonconsensus_block_numbers, %{timeout: timeout}) do
    transaction_query =
      from(transaction in Transaction,
        where: transaction.block_number in ^nonconsensus_block_numbers,
        select: map(transaction, [:hash]),
        order_by: transaction.hash
      )

    ordered_logs =
      from(log in Log,
        inner_join: transaction in subquery(transaction_query),
        on: log.transaction_hash == transaction.hash,
        select: map(log, [:transaction_hash, :index]),
        # Enforce Log ShareLocks order (see docs: sharelocks.md)
        order_by: [
          log.transaction_hash,
          log.index
        ],
        lock: "FOR UPDATE OF l0"
      )

    query =
      from(log in Log,
        select: map(log, [:transaction_hash, :index]),
        inner_join: ordered_log in subquery(ordered_logs),
        on: ordered_log.transaction_hash == log.transaction_hash and ordered_log.index == log.index
      )

    try do
      {_count, deleted_logs} = repo.delete_all(query, timeout: timeout)

      {:ok, deleted_logs}
    rescue
      postgrex_error in Postgrex.Error ->
        {:error, %{exception: postgrex_error, block_numbers: nonconsensus_block_numbers}}
    end
  end

  defp delete_address_token_balances(_, [], _), do: {:ok, []}

  defp delete_address_token_balances(repo, ordered_consensus_block_numbers, %{timeout: timeout}) do
    ordered_query =
      from(address_token_balance in Address.TokenBalance,
        where: address_token_balance.block_number in ^ordered_consensus_block_numbers,
        select: map(address_token_balance, [:address_hash, :token_contract_address_hash, :block_number]),
        # Enforce TokenBalance ShareLocks order (see docs: sharelocks.md)
        order_by: [
          address_token_balance.address_hash,
          address_token_balance.token_contract_address_hash,
          address_token_balance.block_number
        ],
        lock: "FOR UPDATE"
      )

    query =
      from(address_token_balance in Address.TokenBalance,
        select: map(address_token_balance, [:address_hash, :token_contract_address_hash, :block_number]),
        inner_join: ordered_address_token_balance in subquery(ordered_query),
        on:
          ordered_address_token_balance.address_hash == address_token_balance.address_hash and
            ordered_address_token_balance.token_contract_address_hash ==
              address_token_balance.token_contract_address_hash and
            ordered_address_token_balance.block_number == address_token_balance.block_number
      )

    try do
      {_count, deleted_address_token_balances} = repo.delete_all(query, timeout: timeout)

      {:ok, deleted_address_token_balances}
    rescue
      postgrex_error in Postgrex.Error ->
        {:error, %{exception: postgrex_error, block_numbers: ordered_consensus_block_numbers}}
    end
  end

  defp delete_address_current_token_balances(_, [], _), do: {:ok, []}

  defp delete_address_current_token_balances(repo, ordered_consensus_block_numbers, %{timeout: timeout}) do
    ordered_query =
      from(address_current_token_balance in Address.CurrentTokenBalance,
        where: address_current_token_balance.block_number in ^ordered_consensus_block_numbers,
        select: map(address_current_token_balance, [:address_hash, :token_contract_address_hash]),
        # Enforce CurrentTokenBalance ShareLocks order (see docs: sharelocks.md)
        order_by: [
          address_current_token_balance.address_hash,
          address_current_token_balance.token_contract_address_hash
        ],
        lock: "FOR UPDATE"
      )

    query =
      from(address_current_token_balance in Address.CurrentTokenBalance,
        select:
          map(address_current_token_balance, [
            :address_hash,
            :token_contract_address_hash,
            # Used to determine if `address_hash` was a holder of `token_contract_address_hash` before

            # `address_current_token_balance` is deleted in `update_tokens_holder_count`.
            :value
          ]),
        inner_join: ordered_address_current_token_balance in subquery(ordered_query),
        on:
          ordered_address_current_token_balance.address_hash == address_current_token_balance.address_hash and
            ordered_address_current_token_balance.token_contract_address_hash ==
              address_current_token_balance.token_contract_address_hash
      )

    try do
      {_count, deleted_address_current_token_balances} = repo.delete_all(query, timeout: timeout)

      {:ok, deleted_address_current_token_balances}
    rescue
      postgrex_error in Postgrex.Error ->
        {:error, %{exception: postgrex_error, block_numbers: ordered_consensus_block_numbers}}
    end
  end

  defp derive_address_current_token_balances(_, [], _), do: {:ok, []}

  defp derive_address_current_token_balances(repo, deleted_address_current_token_balances, %{timeout: timeout})
       when is_list(deleted_address_current_token_balances) do
    initial_query =
      from(address_token_balance in Address.TokenBalance,
        select: %{
          address_hash: address_token_balance.address_hash,
          token_contract_address_hash: address_token_balance.token_contract_address_hash,
          block_number: max(address_token_balance.block_number)
        },
        group_by: [address_token_balance.address_hash, address_token_balance.token_contract_address_hash]
      )

    final_query =
      Enum.reduce(deleted_address_current_token_balances, initial_query, fn %{
                                                                              address_hash: address_hash,
                                                                              token_contract_address_hash:
                                                                                token_contract_address_hash
                                                                            },
                                                                            acc_query ->
        from(address_token_balance in acc_query,
          or_where:
            address_token_balance.address_hash == ^address_hash and
              address_token_balance.token_contract_address_hash == ^token_contract_address_hash
        )
      end)

    new_current_token_balance_query =
      from(new_current_token_balance in subquery(final_query),
        inner_join: address_token_balance in Address.TokenBalance,
        on:
          address_token_balance.address_hash == new_current_token_balance.address_hash and
            address_token_balance.token_contract_address_hash == new_current_token_balance.token_contract_address_hash and
            address_token_balance.block_number == new_current_token_balance.block_number,
        select: %{
          address_hash: new_current_token_balance.address_hash,
          token_contract_address_hash: new_current_token_balance.token_contract_address_hash,
          block_number: new_current_token_balance.block_number,
          value: address_token_balance.value,
          inserted_at: over(min(address_token_balance.inserted_at), :w),
          updated_at: over(max(address_token_balance.updated_at), :w)
        },
        windows: [
          w: [partition_by: [address_token_balance.address_hash, address_token_balance.token_contract_address_hash]]
        ]
      )

    multi =
      Multi.new()
      |> Multi.run(:new_current_token_balance, fn repo, _ ->
        new_current_token_balances = repo.all(new_current_token_balance_query)
        {:ok, new_current_token_balances}
      end)
      |> Multi.run(
        :insert_new_current_token_balance,
        fn repo, %{new_current_token_balance: new_current_token_balance} ->
          # Enforce CurrentTokenBalance ShareLocks order (see docs: sharelocks.md)
          ordered_current_token_balance =
            Enum.sort_by(
              new_current_token_balance,
              &{&1.address_hash, &1.token_contract_address_hash}
            )

          {_total, result} =
            repo.insert_all(
              Address.CurrentTokenBalance,
              ordered_current_token_balance,
              # No `ON CONFLICT` because `delete_address_current_token_balances`
              # should have removed any conflicts.
              returning: [:address_hash, :token_contract_address_hash, :block_number, :value]
            )

          {:ok, result}
        end
      )

    with {:ok, %{insert_new_current_token_balance: rows}} <- repo.transaction(multi, timeout: timeout) do
      derived_address_current_token_balances =
        Enum.map(rows, &Map.take(&1, [:address_hash, :token_contract_address_hash, :block_number, :value]))

      {:ok, derived_address_current_token_balances}
    end
  end

  # `block_rewards` are linked to `blocks.hash`, but fetched by `blocks.number`, so when a block with the same number is
  # inserted, the old block rewards need to be deleted, so that the old and new rewards aren't combined.
  defp delete_rewards(repo, blocks_changes, %{timeout: timeout}) do
    {hashes, numbers} =
      Enum.reduce(blocks_changes, {[], []}, fn
        %{consensus: false, hash: hash}, {acc_hashes, acc_numbers} ->
          {[hash | acc_hashes], acc_numbers}

        %{consensus: true, number: number}, {acc_hashes, acc_numbers} ->
          {acc_hashes, [number | acc_numbers]}
      end)

    query =
      from(reward in Reward,
        inner_join: block in assoc(reward, :block),
        where: block.hash in ^hashes or block.number in ^numbers,
        # Enforce Reward ShareLocks order (see docs: sharelocks.md)
        order_by: [asc: :address_hash, asc: :address_type, asc: :block_hash],
        # NOTE: find a better way to know the alias that ecto gives to token
        lock: "FOR UPDATE OF b0"
      )

    delete_query =
      from(r in Reward,
        join: s in subquery(query),
        on:
          r.address_hash == s.address_hash and
            r.address_type == s.address_type and
            r.block_hash == s.block_hash
      )

    try do
      {count, nil} = repo.delete_all(delete_query, timeout: timeout)

      {:ok, count}
    rescue
      postgrex_error in Postgrex.Error ->
        {:error, %{exception: postgrex_error, blocks_changes: blocks_changes}}
    end
  end

  defp update_block_second_degree_relations(repo, blocks, %{timeout: timeout, timestamps: %{updated_at: updated_at}})
       when is_list(blocks) do
    uncle_hashes =
      blocks
      |> MapSet.new(& &1.hash)
      |> MapSet.to_list()

    query =
      from(
        bsdr in Block.SecondDegreeRelation,
        where: bsdr.uncle_hash in ^uncle_hashes,
        # Enforce SeconDegreeRelation ShareLocks order (see docs: sharelocks.md)
        order_by: [asc: :nephew_hash, asc: :uncle_hash],
        lock: "FOR UPDATE"
      )

    update_query =
      from(
        b in Block.SecondDegreeRelation,
        join: s in subquery(query),
        on: b.nephew_hash == s.nephew_hash and b.uncle_hash == s.uncle_hash,
        update: [set: [uncle_fetched_at: ^updated_at]]
      )

    try do
      {_, result} = repo.update_all(update_query, [], timeout: timeout)

      {:ok, result}
    rescue
      postgrex_error in Postgrex.Error ->
        {:error, %{exception: postgrex_error, uncle_hashes: uncle_hashes}}
    end
  end

  defp update_internal_transaction_block_number(repo, blocks) when is_list(blocks) do
    blocks_hashes = Enum.map(blocks, & &1.hash)

    query =
      from(
        internal_transaction in InternalTransaction,
        join: transaction in Transaction,
        on: internal_transaction.transaction_hash == transaction.hash,
        join: block in Block,
        on: block.hash == transaction.block_hash,
        where: block.hash in ^blocks_hashes,
        select: %{
          transaction_hash: internal_transaction.transaction_hash,
          index: internal_transaction.index,
          block_number: block.number
        },
        # Enforce InternalTransaction ShareLocks order (see docs: sharelocks.md)
        order_by: [asc: :transaction_hash, asc: :index],
        # NOTE: find a better way to know the alias that ecto gives to internal_transaction
        lock: "FOR UPDATE OF i0"
      )

    update_query =
      from(
        i in InternalTransaction,
        join: s in subquery(query),
        on: i.transaction_hash == s.transaction_hash and i.index == s.index,
        update: [set: [block_number: s.block_number]]
      )

    {total, _} = repo.update_all(update_query, [])

    {:ok, total}
  end

  defp where_forked(blocks_changes) when is_list(blocks_changes) do
    initial = from(t in Transaction, where: false)

    Enum.reduce(blocks_changes, initial, fn %{consensus: consensus, hash: hash, number: number}, acc ->
      if consensus do
        from(transaction in acc, or_where: transaction.block_hash != ^hash and transaction.block_number == ^number)
      else
        from(transaction in acc, or_where: transaction.block_hash == ^hash and transaction.block_number == ^number)
      end
    end)
  end

  defp where_invalid_neighbour(blocks_changes) when is_list(blocks_changes) do
    initial = from(b in Block, where: false)

    Enum.reduce(blocks_changes, initial, fn %{
                                              consensus: consensus,
                                              hash: hash,
                                              parent_hash: parent_hash,
                                              number: number
                                            },
                                            acc ->
      if consensus do
        from(
          block in acc,
          or_where: block.number == ^(number - 1) and block.hash != ^parent_hash,
          or_where: block.number == ^(number + 1) and block.parent_hash != ^hash
        )
      else
        acc
      end
    end)
  end
end
