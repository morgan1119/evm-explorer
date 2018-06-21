defmodule Explorer.Indexer.InternalTransactionFetcher do
  @moduledoc """
  Fetches and indexes `t:Explorer.Chain.InternalTransaction.t/0`.

  See `async_fetch/1` for details on configuring limits.
  """

  require Logger

  alias Explorer.{BufferedTask, Chain, Indexer}
  alias Explorer.Indexer.{AddressBalanceFetcher, AddressExtraction}
  alias Explorer.Chain.{Block, Hash}

  @behaviour BufferedTask

  @max_batch_size 10
  @max_concurrency 4
  @defaults [
    flush_interval: :timer.seconds(3),
    max_concurrency: @max_concurrency,
    max_batch_size: @max_batch_size,
    init_chunk_size: 5000,
    task_supervisor: Explorer.Indexer.TaskSupervisor
  ]

  @doc """
  Asynchronously fetches internal transactions.

  ## Limiting Upstream Load

  Internal transactions are an expensive upstream operation. The number of
  results to fetch is configured by `@max_batch_size` and represents the number
  of transaction hashes to request internal transactions in a single JSONRPC
  request. Defaults to `#{@max_batch_size}`.

  The `@max_concurrency` attribute configures the  number of concurrent requests
  of `@max_batch_size` to allow against the JSONRPC. Defaults to `#{@max_concurrency}`.

  *Note*: The internal transactions for individual transactions cannot be paginated,
  so the total number of internal transactions that could be produced is unknown.
  """
  @spec async_fetch([%{required(:block_number) => Block.block_number(), required(:hash) => Hash.Full.t()}]) :: :ok
  def async_fetch(transactions_fields, timeout \\ 5000) when is_list(transactions_fields) do
    params_list = Enum.map(transactions_fields, &transaction_fields_to_params/1)

    BufferedTask.buffer(__MODULE__, params_list, timeout)
  end

  @doc false
  def child_spec(provided_opts) do
    opts = Keyword.merge(@defaults, provided_opts)
    Supervisor.child_spec({BufferedTask, {__MODULE__, opts}}, id: __MODULE__)
  end

  @impl BufferedTask
  def init(initial, reducer) do
    {:ok, final} =
      Chain.stream_transactions_with_unfetched_internal_transactions(
        [:block_number, :hash],
        initial,
        fn transaction_fields, acc ->
          transaction_fields
          |> transaction_fields_to_params()
          |> reducer.(acc)
        end
      )

    final
  end

  defp transaction_fields_to_params(%{block_number: block_number, hash: hash}) when is_integer(block_number) do
    %{block_number: block_number, hash_data: to_string(hash)}
  end

  @impl BufferedTask
  def run(transactions_params, _retries) do
    unique_transactions_params = unique_transactions_params(transactions_params)

    Indexer.debug(fn -> "fetching internal transactions for #{length(unique_transactions_params)} transactions" end)

    case EthereumJSONRPC.fetch_internal_transactions(unique_transactions_params) do
      {:ok, internal_transactions_params} ->
        addresses_params = AddressExtraction.extract_addresses(%{internal_transactions: internal_transactions_params})

        address_hash_to_block_number =
          Enum.into(addresses_params, %{}, fn %{fetched_balance_block_number: block_number, hash: hash} ->
            {hash, block_number}
          end)

        transaction_hashes = Enum.map(unique_transactions_params, &Map.fetch!(&1, :hash_data))

        with {:ok, %{addresses: address_hashes}} <-
               Chain.import_internal_transactions(
                 addresses: [params: addresses_params],
                 internal_transactions: [params: internal_transactions_params],
                 transactions: [hashes: transaction_hashes]
               ) do
          address_hashes
          |> Enum.map(fn address_hash ->
            block_number = Map.fetch!(address_hash_to_block_number, to_string(address_hash))
            %{block_number: block_number, hash: address_hash}
          end)
          |> AddressBalanceFetcher.async_fetch_balances()
        else
          {:error, step, reason, _changes_so_far} ->
            Indexer.debug(fn ->
              [
                "failed to import internal transactions for ",
                to_string(length(transactions_params)),
                " transactions at ",
                to_string(step),
                ": ",
                inspect(reason)
              ]
            end)

            # re-queue the de-duped transactions_params
            {:retry, unique_transactions_params}
        end

      {:error, reason} ->
        Indexer.debug(fn ->
          "failed to fetch internal transactions for #{length(transactions_params)} transactions: #{inspect(reason)}"
        end)

        # re-queue the de-duped transactions_params
        {:retry, unique_transactions_params}
    end
  end

  # Protection and improved reporting for https://github.com/poanetwork/poa-explorer/issues/289
  defp unique_transactions_params(transactions_params) do
    transaactions_params_by_hash_data = Enum.group_by(transactions_params, fn %{hash_data: hash_data} -> hash_data end)

    if map_size(transaactions_params_by_hash_data) < length(transactions_params) do
      {unique_transactions_params, duplicate_transactions_params} =
        transaactions_params_by_hash_data
        |> Map.values()
        |> uniques_and_duplicates()

      Logger.error(fn ->
        duplicate_transactions_params
        |> Stream.with_index()
        |> Enum.reduce(
          ["Duplicate transaction params being used to fetch internal transactions:\n"],
          fn {transaction_params, index}, acc ->
            [acc, "  ", to_string(index + 1), ". ", inspect(transaction_params), "\n"]
          end
        )
      end)

      unique_transactions_params
    else
      transactions_params
    end
  end

  defp uniques_and_duplicates(groups) do
    Enum.reduce(groups, {[], []}, fn group, {acc_uniques, acc_duplicates} ->
      case group do
        [unique] ->
          {[unique | acc_uniques], acc_duplicates}

        [unique | _] = duplicates ->
          {[unique | acc_uniques], duplicates ++ acc_duplicates}
      end
    end)
  end
end
