defmodule Indexer.AddressBalanceFetcher do
  @moduledoc """
  Fetches `t:Explorer.Chain.Address.t/0` `fetched_balance`.
  """

  import EthereumJSONRPC, only: [integer_to_quantity: 1]

  alias Explorer.Chain
  alias Explorer.Chain.{Block, Hash}
  alias Indexer.BufferedTask

  @behaviour BufferedTask

  @defaults [
    flush_interval: :timer.seconds(3),
    max_batch_size: 500,
    max_concurrency: 4,
    init_chunk_size: 1000,
    task_supervisor: Indexer.TaskSupervisor
  ]

  @doc """
  Asynchronously fetches balances for each address `hash` at the `block_number`.
  """
  @spec async_fetch_balances([%{required(:block_number) => Block.block_number(), required(:hash) => Hash.Address.t()}]) ::
          :ok
  def async_fetch_balances(address_fields) when is_list(address_fields) do
    params_list = Enum.map(address_fields, &address_fields_to_params/1)

    BufferedTask.buffer(__MODULE__, params_list)
  end

  @doc false
  def child_spec(provided_opts) do
    {state, mergable_opts} = Keyword.pop(provided_opts, :json_rpc_named_arguments)

    unless state do
      raise ArgumentError,
            ":json_rpc_named_arguments must be provided to `#{__MODULE__}.child_spec " <>
              "to allow for json_rpc calls when running."
    end

    opts =
      @defaults
      |> Keyword.merge(mergable_opts)
      |> Keyword.put(:state, state)

    Supervisor.child_spec({BufferedTask, {__MODULE__, opts}}, id: __MODULE__)
  end

  @impl BufferedTask
  def init(initial, reducer, _) do
    {:ok, final} =
      Chain.stream_unfetched_addresses(initial, fn address_fields, acc ->
        address_fields
        |> address_fields_to_params()
        |> reducer.(acc)
      end)

    final
  end

  @impl BufferedTask
  def run(params_list, _retries, json_rpc_named_arguments) do
    latest_params_list = latest_params_list(params_list)

    Indexer.debug(fn -> "fetching #{length(latest_params_list)} balances" end)

    case EthereumJSONRPC.fetch_balances(latest_params_list, json_rpc_named_arguments) do
      {:ok, addresses_params} ->
        {:ok, _} = Chain.update_balances(addresses_params)
        :ok

      {:error, reason} ->
        Indexer.debug(fn -> "failed to fetch #{length(latest_params_list)} balances, #{inspect(reason)}" end)
        {:retry, latest_params_list}
    end
  end

  defp address_fields_to_params(%{block_number: block_number, hash: hash}) when is_integer(block_number) do
    %{block_quantity: integer_to_quantity(block_number), hash_data: to_string(hash)}
  end

  # when there are duplicate `hash`, favors max `block_number` to mimic `on_conflict` in
  # `Explorer.Chain.insert_addresses` to fix https://github.com/poanetwork/poa-explorer/issues/309
  defp latest_params_list(params_list) do
    params_list
    |> Enum.group_by(fn %{hash_data: hash_data} -> hash_data end)
    |> Map.values()
    |> Enum.map(&Enum.max_by(&1, fn %{block_quantity: block_quantity} -> block_quantity end))
  end
end
