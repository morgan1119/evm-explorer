defmodule ExplorerWeb.EventHandler do
  @moduledoc """
  Subscribing process for broadcast events from Chain context.
  """

  use GenServer
  alias Explorer.Chain
  alias ExplorerWeb.Notifier

  # Client

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Server

  def init([]) do
    Chain.subscribe_to_events(:addresses)
    Chain.subscribe_to_events(:blocks)
    Chain.subscribe_to_events(:transactions)
    {:ok, []}
  end

  def handle_info(event, state) do
    Notifier.handle_event(event)
    {:noreply, state}
  end
end
