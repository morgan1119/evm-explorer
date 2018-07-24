defmodule Indexer.Application do
  @moduledoc """
  This is the `Application` module for `Indexer`.
  """

  use Application

  alias Indexer.{BalanceFetcher, BlockFetcher, InternalTransactionFetcher, PendingTransactionFetcher}

  @impl Application
  def start(_type, _args) do
    json_rpc_named_arguments = Application.fetch_env!(:indexer, :json_rpc_named_arguments)

    children = [
      {Task.Supervisor, name: Indexer.TaskSupervisor},
      {BalanceFetcher, name: BalanceFetcher, json_rpc_named_arguments: json_rpc_named_arguments},
      {PendingTransactionFetcher, name: PendingTransactionFetcher, json_rpc_named_arguments: json_rpc_named_arguments},
      {InternalTransactionFetcher,
       name: InternalTransactionFetcher, json_rpc_named_arguments: json_rpc_named_arguments},
      {BlockFetcher, []}
    ]

    opts = [strategy: :one_for_one, name: Indexer.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
