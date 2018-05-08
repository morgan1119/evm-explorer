defmodule Explorer.Chain.Statistics.Server do
  @moduledoc "Stores the latest chain statistics."

  use GenServer

  alias Explorer.Chain.Statistics

  @interval 1_000

  def child_spec(_) do
    Supervisor.Spec.worker(__MODULE__, [[refresh: true]])
  end

  @spec fetch() :: Statistics.t()
  def fetch do
    case GenServer.whereis(__MODULE__) do
      nil -> Statistics.fetch()
      _ -> GenServer.call(__MODULE__, :fetch)
    end
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(options) when is_list(options) do
    if Keyword.get(options, :refresh, true) do
      send(self(), :refresh)
    end

    {:ok, %Statistics{}}
  end

  def handle_info(:refresh, %Statistics{} = statistics) do
    Task.start_link(fn ->
      GenServer.cast(__MODULE__, {:update, Statistics.fetch()})
    end)

    {:noreply, statistics}
  end

  def handle_info(_, %Statistics{} = statistics), do: {:noreply, statistics}
  def handle_call(:fetch, _, %Statistics{} = statistics), do: {:reply, statistics, statistics}
  def handle_call(_, _, %Statistics{} = statistics), do: {:noreply, statistics}

  def handle_cast({:update, %Statistics{} = statistics}, %Statistics{} = _) do
    Process.send_after(self(), :refresh, @interval)
    {:noreply, statistics}
  end

  def handle_cast(_, %Statistics{} = statistics), do: {:noreply, statistics}
end
