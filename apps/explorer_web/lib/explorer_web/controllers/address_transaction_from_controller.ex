defmodule ExplorerWeb.AddressTransactionFromController do
  @moduledoc """
    Display all the Transactions that originate at this Address.
  """

  use ExplorerWeb, :controller

  alias Explorer.Chain
  alias ExplorerWeb.TransactionForm

  def index(conn, %{"address_id" => from_address_hash} = params) do
    case Chain.hash_to_address(from_address_hash) do
      {:ok, from_address} ->
        page =
          Chain.from_address_to_transactions(
            from_address,
            necessity_by_association: %{
              block: :required,
              from_address: :optional,
              to_address: :optional,
              receipt: :required
            },
            pagination: params
          )

        entries = Enum.map(page.entries, &TransactionForm.build_and_merge/1)
        render(conn, "index.html", transactions: Map.put(page, :entries, entries))

      {:error, :not_found} ->
        not_found(conn)
    end
  end
end
