defmodule ExplorerWeb.TransactionInternalTransactionController do
  use ExplorerWeb, :controller

  import ExplorerWeb.Chain, only: [paging_options: 1]

  alias Explorer.{Chain, Market}
  alias Explorer.ExchangeRates.Token

  @page_size 50

  def index(conn, %{"transaction_id" => hash_string} = params) do
    with {:ok, hash} <- Chain.string_to_transaction_hash(hash_string),
         {:ok, transaction} <-
           Chain.hash_to_transaction(
             hash,
             necessity_by_association: %{
               block: :optional,
               from_address: :optional,
               to_address: :optional
             }
           ) do
      full_options =
        [
          necessity_by_association: %{
            from_address: :required,
            to_address: :optional
          }
        ]
        |> Keyword.merge(paging_options(params))

      internal_transactions_plus_one = Chain.transaction_to_internal_transactions(transaction, full_options)

      {internal_transactions, next_page} = Enum.split(internal_transactions_plus_one, @page_size)

      max_block_number = max_block_number()

      render(
        conn,
        "index.html",
        exchange_rate: Market.get_exchange_rate(Explorer.coin()) || Token.null(),
        internal_transactions: internal_transactions,
        max_block_number: max_block_number,
        next_page_params: next_page_params(next_page, internal_transactions),
        transaction: transaction
      )
    else
      :error ->
        not_found(conn)

      {:error, :not_found} ->
        not_found(conn)
    end
  end

  defp max_block_number do
    case Chain.max_block_number() do
      {:ok, number} -> number
      {:error, :not_found} -> 0
    end
  end

  defp next_page_params([], _internal_transactions), do: nil

  defp next_page_params(_, internal_transactions) do
    last = List.last(internal_transactions)
    %{index: last.index}
  end
end
