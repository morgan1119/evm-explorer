defmodule Indexer.BlockFetcher do
  @moduledoc """
  Fetches and indexes block ranges from gensis to realtime.
  """

  use GenServer

  require Logger

  import Indexer, only: [debug: 1]

  alias EthereumJSONRPC
  alias Explorer.Chain
  alias Indexer.{BalanceFetcher, AddressExtraction, BoundInterval, InternalTransactionFetcher, Sequence}

  # dialyzer thinks that Logger.debug functions always have no_local_return
  @dialyzer {:nowarn_function, import_range: 3}

  # These are all the *default* values for options.
  # DO NOT use them directly in the code.  Get options from `state`.

  @blocks_batch_size 10
  @blocks_concurrency 10

  # milliseconds
  @block_interval 5_000

  @receipts_batch_size 250
  @receipts_concurrency 10

  @doc false
  def default_blocks_batch_size, do: @blocks_batch_size

  @doc """
  Starts the server.

  ## Options

  Default options are pulled from application config under the :indexer` keyspace. The follow options can be overridden:

    * `:blocks_batch_size` - The number of blocks to request in one call to the JSONRPC.  Defaults to
      `#{@blocks_batch_size}`.  Block requests also include the transactions for those blocks.  *These transactions
      are not paginated.*
    * `:blocks_concurrency` - The number of concurrent requests of `:blocks_batch_size` to allow against the JSONRPC.
      Defaults to #{@blocks_concurrency}.  So upto `blocks_concurrency * block_batch_size` (defaults to
      `#{@blocks_concurrency * @blocks_batch_size}`) blocks can be requested from the JSONRPC at once over all
      connections.
    * `:block_interval` - The number of milliseconds between new blocks being published. Defaults to
        `#{@block_interval}` milliseconds.
    * `:receipts_batch_size` - The number of receipts to request in one call to the JSONRPC.  Defaults to
      `#{@receipts_batch_size}`.  Receipt requests also include the logs for when the transaction was collated into the
      block.  *These logs are not paginated.*
    * `:receipts_concurrency` - The number of concurrent requests of `:receipts_batch_size` to allow against the JSONRPC
      **for each block range**. Defaults to `#{@receipts_concurrency}`.  So upto
      `block_concurrency * receipts_batch_size * receipts_concurrency` (defaults to
      `#{@blocks_concurrency * @receipts_concurrency * @receipts_batch_size}`) receipts can be requested from the
      JSONRPC at once over all connections. *Each transaction only has one receipt.*
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  defstruct json_rpc_named_arguments: [],
            catchup_task: nil,
            catchup_block_number: nil,
            catchup_bound_interval: nil,
            realtime_task_by_ref: %{},
            realtime_interval: nil,
            blocks_batch_size: @blocks_batch_size,
            blocks_concurrency: @blocks_concurrency,
            receipts_batch_size: @receipts_batch_size,
            receipts_concurrency: @receipts_concurrency

  @impl GenServer
  def init(opts) do
    opts =
      :indexer
      |> Application.get_all_env()
      |> Keyword.merge(opts)

    interval = div(opts[:block_interval] || @block_interval, 2)

    state = %__MODULE__{
      json_rpc_named_arguments: Keyword.fetch!(opts, :json_rpc_named_arguments),
      catchup_bound_interval: BoundInterval.within(interval..(interval * 10)),
      realtime_interval: interval,
      blocks_batch_size: Keyword.get(opts, :blocks_batch_size, @blocks_batch_size),
      blocks_concurrency: Keyword.get(opts, :blocks_concurrency, @blocks_concurrency),
      receipts_batch_size: Keyword.get(opts, :receipts_batch_size, @receipts_batch_size),
      receipts_concurrency: Keyword.get(opts, :receipts_concurrency, @receipts_concurrency)
    }

    send(self(), :catchup_index)
    {:ok, _} = :timer.send_interval(state.realtime_interval, :realtime_index)

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:catchup_index, %__MODULE__{} = state) do
    catchup_task = Task.Supervisor.async_nolink(Indexer.TaskSupervisor, fn -> catchup_task(state) end)

    {:noreply, %{state | catchup_task: catchup_task}}
  end

  def handle_info(
        {ref, missing_block_count},
        %__MODULE__{
          catchup_block_number: catchup_block_number,
          catchup_bound_interval: catchup_bound_interval,
          catchup_task: %Task{ref: ref}
        } = state
      )
      when is_integer(missing_block_count) do
    new_catchup_bound_interval =
      case missing_block_count do
        0 ->
          Logger.info("Index already caught up in #{catchup_block_number}-0")

          BoundInterval.increase(catchup_bound_interval)

        _ ->
          Logger.info("Index had to catch up #{missing_block_count} blocks in #{catchup_block_number}-0")

          BoundInterval.decrease(catchup_bound_interval)
      end

    Process.demonitor(ref, [:flush])

    interval = new_catchup_bound_interval.current

    Logger.info(fn ->
      "Checking if index needs to catch up in #{interval}ms"
    end)

    Process.send_after(self(), :catchup_index, interval)

    {:noreply, %{state | catchup_bound_interval: new_catchup_bound_interval, catchup_task: nil}}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, %__MODULE__{catchup_task: %Task{pid: pid, ref: ref}} = state) do
    Logger.error(fn -> "Catchup index stream exited with reason (#{inspect(reason)}). Restarting" end)

    send(self(), :catchup_index)

    {:noreply, %__MODULE__{state | catchup_task: nil}}
  end

  def handle_info(:realtime_index, %__MODULE__{} = state) do
    %Task{ref: ref} =
      realtime_task = Task.Supervisor.async_nolink(Indexer.TaskSupervisor, fn -> realtime_task(state) end)

    new_state = put_in(state.realtime_task_by_ref[ref], realtime_task)

    {:noreply, new_state}
  end

  def handle_info({ref, :ok = result}, %__MODULE__{realtime_task_by_ref: realtime_task_by_ref} = state) do
    {realtime_task, running_realtime_task_by_ref} = Map.pop(realtime_task_by_ref, ref)

    case realtime_task do
      nil ->
        Logger.error(fn ->
          "Unknown ref (#{inspect(ref)}) that is neither the catchup index" <>
            " nor a realtime index Task ref returned result (#{inspect(result)})"
        end)

      _ ->
        :ok
    end

    Process.demonitor(ref, [:flush])

    {:noreply, %__MODULE__{state | realtime_task_by_ref: running_realtime_task_by_ref}}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, %__MODULE__{realtime_task_by_ref: realtime_task_by_ref} = state) do
    {realtime_task, running_realtime_task_by_ref} = Map.pop(realtime_task_by_ref, ref)

    case realtime_task do
      nil ->
        Logger.error(fn ->
          "Unknown ref (#{inspect(ref)}) that is neither the catchup index" <>
            " nor a realtime index Task ref reports unknown pid (#{pid}) DOWN due to reason (#{reason}})"
        end)

      _ ->
        Logger.error(fn ->
          "Realtime index stream exited with reason (#{inspect(reason)}).  " <>
            "The next realtime index task will fill the missing block " <>
            "if the lastest block number has not advanced by then or the catch up index will fill the missing block."
        end)
    end

    {:noreply, %__MODULE__{state | realtime_task_by_ref: running_realtime_task_by_ref}}
  end

  defp cap_seq(seq, next, range) do
    case next do
      :more ->
        debug(fn ->
          first_block_number..last_block_number = range
          "got blocks #{first_block_number} - #{last_block_number}"
        end)

      :end_of_chain ->
        Sequence.cap(seq)
    end

    :ok
  end

  defp fetch_transaction_receipts(%__MODULE__{} = _state, []), do: {:ok, %{logs: [], receipts: []}}

  defp fetch_transaction_receipts(
         %__MODULE__{json_rpc_named_arguments: json_rpc_named_arguments} = state,
         transaction_params
       ) do
    debug(fn -> "fetching #{length(transaction_params)} transaction receipts" end)
    stream_opts = [max_concurrency: state.receipts_concurrency, timeout: :infinity]

    transaction_params
    |> Enum.chunk_every(state.receipts_batch_size)
    |> Task.async_stream(&EthereumJSONRPC.fetch_transaction_receipts(&1, json_rpc_named_arguments), stream_opts)
    |> Enum.reduce_while({:ok, %{logs: [], receipts: []}}, fn
      {:ok, {:ok, %{logs: logs, receipts: receipts}}}, {:ok, %{logs: acc_logs, receipts: acc_receipts}} ->
        {:cont, {:ok, %{logs: acc_logs ++ logs, receipts: acc_receipts ++ receipts}}}

      {:ok, {:error, reason}}, {:ok, _acc} ->
        {:halt, {:error, reason}}

      {:error, reason}, {:ok, _acc} ->
        {:halt, {:error, reason}}
    end)
  end

  # Returns number of missing blocks that had to be caught up
  defp catchup_task(%__MODULE__{json_rpc_named_arguments: json_rpc_named_arguments} = state) do
    {:ok, latest_block_number} = EthereumJSONRPC.fetch_block_number_by_tag("latest", json_rpc_named_arguments)

    case latest_block_number do
      # let realtime indexer get the genesis block
      0 ->
        0

      _ ->
        # realtime indexer gets the current latest block
        first = latest_block_number - 1
        last = 0
        missing_ranges = Chain.missing_block_number_ranges(first..last)
        range_count = Enum.count(missing_ranges)

        missing_block_count =
          missing_ranges
          |> Stream.map(&Enum.count/1)
          |> Enum.sum()

        debug(fn -> "#{missing_block_count} missed blocks in #{range_count} ranges between #{first} and #{last}" end)

        case missing_block_count do
          0 ->
            :ok

          _ ->
            {:ok, seq} = Sequence.start_link(ranges: missing_ranges, step: -1 * state.blocks_batch_size)
            Sequence.cap(seq)

            stream_import(state, seq, max_concurrency: state.blocks_concurrency)
        end

        missing_block_count
    end
  end

  defp insert(seq, range, options) when is_list(options) do
    {address_hash_to_fetched_balance_block_number, import_options} =
      pop_address_hash_to_fetched_balance_block_number(options)

    transaction_hash_to_block_number = get_transaction_hash_to_block_number(import_options)

    with {:ok, results} <- Chain.import_blocks(import_options) do
      async_import_remaining_block_data(
        results,
        address_hash_to_fetched_balance_block_number: address_hash_to_fetched_balance_block_number,
        transaction_hash_to_block_number: transaction_hash_to_block_number
      )

      {:ok, results}
    else
      {:error, step, failed_value, _changes_so_far} = error ->
        debug(fn ->
          "failed to insert blocks during #{step} #{inspect(range)}: #{inspect(failed_value)}. Retrying"
        end)

        :ok = Sequence.queue(seq, range)

        error
    end
  end

  # `fetched_balance_block_number` is needed for the `BalanceFetcher`, but should not be used for
  # `import_blocks` because the balance is not known yet.
  defp pop_address_hash_to_fetched_balance_block_number(options) do
    {address_hash_fetched_balance_block_number_pairs, import_options} =
      get_and_update_in(options, [:addresses, :params, Access.all()], &pop_hash_fetched_balance_block_number/1)

    address_hash_to_fetched_balance_block_number = Map.new(address_hash_fetched_balance_block_number_pairs)
    {address_hash_to_fetched_balance_block_number, import_options}
  end

  defp get_transaction_hash_to_block_number(options) do
    options
    |> get_in([:transactions, :params, Access.all()])
    |> Enum.into(%{}, fn %{block_number: block_number, hash: hash} ->
      {hash, block_number}
    end)
  end

  defp pop_hash_fetched_balance_block_number(
         %{
           fetched_balance_block_number: fetched_balance_block_number,
           hash: hash
         } = address_params
       ) do
    {{hash, fetched_balance_block_number}, Map.delete(address_params, :fetched_balance_block_number)}
  end

  defp async_import_remaining_block_data(results, named_arguments) when is_map(results) and is_list(named_arguments) do
    %{transactions: transaction_hashes, addresses: address_hashes} = results
    address_hash_to_block_number = Keyword.fetch!(named_arguments, :address_hash_to_fetched_balance_block_number)

    address_hashes
    |> Enum.map(fn address_hash ->
      block_number = Map.fetch!(address_hash_to_block_number, to_string(address_hash))
      %{address_hash: address_hash, block_number: block_number}
    end)
    |> BalanceFetcher.async_fetch_balances()

    transaction_hash_to_block_number = Keyword.fetch!(named_arguments, :transaction_hash_to_block_number)

    transaction_hashes
    |> Enum.map(fn transaction_hash ->
      block_number = Map.fetch!(transaction_hash_to_block_number, to_string(transaction_hash))
      %{block_number: block_number, hash: transaction_hash}
    end)
    |> InternalTransactionFetcher.async_fetch(10_000)
  end

  defp realtime_task(%__MODULE__{json_rpc_named_arguments: json_rpc_named_arguments} = state) do
    {:ok, latest_block_number} = EthereumJSONRPC.fetch_block_number_by_tag("latest", json_rpc_named_arguments)
    {:ok, seq} = Sequence.start_link(first: latest_block_number, step: 2)
    stream_import(state, seq, max_concurrency: 1)
  end

  defp stream_import(%__MODULE__{} = state, seq, task_opts) do
    seq
    |> Sequence.build_stream()
    |> Task.async_stream(
      &import_range(&1, state, seq),
      Keyword.merge(task_opts, timeout: :infinity)
    )
    |> Stream.run()
  end

  # Run at state.blocks_concurrency max_concurrency when called by `stream_import/3`
  # Only public for testing
  @doc false
  def import_range(range, %__MODULE__{json_rpc_named_arguments: json_rpc_named_arguments} = state, seq) do
    with {:blocks, {:ok, next, result}} <-
           {:blocks, EthereumJSONRPC.fetch_blocks_by_range(range, json_rpc_named_arguments)},
         %{blocks: blocks, transactions: transactions_without_receipts} = result,
         cap_seq(seq, next, range),
         {:receipts, {:ok, receipt_params}} <-
           {:receipts, fetch_transaction_receipts(state, transactions_without_receipts)},
         %{logs: logs, receipts: receipts} = receipt_params,
         transactions_with_receipts = put_receipts(transactions_without_receipts, receipts) do
      addresses =
        AddressExtraction.extract_addresses(%{
          blocks: blocks,
          logs: logs,
          transactions: transactions_with_receipts
        })

      insert(
        seq,
        range,
        addresses: [params: addresses],
        blocks: [params: blocks],
        logs: [params: logs],
        receipts: [params: receipts],
        transactions: [on_conflict: :replace_all, params: transactions_with_receipts]
      )
    else
      {step, {:error, reason}} ->
        debug(fn ->
          first..last = range
          "failed to fetch #{step} for blocks #{first} - #{last}: #{inspect(reason)}. Retrying block range."
        end)

        :ok = Sequence.queue(seq, range)

        {:error, step, reason}
    end
  end

  defp put_receipts(transactions_params, receipts_params)
       when is_list(transactions_params) and is_list(receipts_params) do
    transaction_hash_to_receipt_params =
      Enum.into(receipts_params, %{}, fn %{transaction_hash: transaction_hash} = receipt_params ->
        {transaction_hash, receipt_params}
      end)

    Enum.map(transactions_params, fn %{hash: transaction_hash} = transaction_params ->
      Map.merge(transaction_params, Map.fetch!(transaction_hash_to_receipt_params, transaction_hash))
    end)
  end
end
