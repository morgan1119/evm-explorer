defmodule ExplorerWeb.Notifier do
  @moduledoc """
  Responds to events from EventHandler by sending appropriate channel updates to front-end.
  """

  alias Explorer.{Chain, Market}
  alias Explorer.Chain.Address
  alias Explorer.ExchangeRates.Token
  alias ExplorerWeb.Endpoint

  def handle_event({:chain_event, :addresses, addresses}) do
    addresses
    |> Stream.reject(fn %Address{fetched_balance: fetched_balance} -> is_nil(fetched_balance) end)
    |> Enum.each(&broadcast_balance/1)
  end

  def handle_event({:chain_event, :blocks, blocks}) do
    max_numbered_block = Enum.max_by(blocks, & &1.number).number
    Endpoint.broadcast("transactions:confirmations", "update", %{block_number: max_numbered_block})
  end

  def handle_event({:chain_event, :transactions, transaction_hashes}) do
    Enum.each(transaction_hashes, &broadcast_transaction/1)
  end

  defp broadcast_balance(%Address{hash: address_hash} = address) do
    Endpoint.broadcast("addresses:#{address_hash}", "balance_update", %{
      address: address,
      exchange_rate: Market.get_exchange_rate(Explorer.coin()) || Token.null()
    })
  end

  defp broadcast_transaction(transaction_hash) do
    case Chain.hash_to_transaction(
           transaction_hash,
           necessity_by_association: %{block: :required, from_address: :optional, to_address: :optional}
         ) do
      {:ok, transaction} ->
        Endpoint.broadcast("addresses:#{transaction.from_address_hash}", "transaction", %{
          address: transaction.from_address,
          transaction: transaction
        })

        if transaction.to_address_hash && transaction.to_address_hash != transaction.from_address_hash do
          Endpoint.broadcast("addresses:#{transaction.to_address_hash}", "transaction", %{
            address: transaction.to_address,
            transaction: transaction
          })
        end

      {:error, _} ->
        nil
    end
  end
end
