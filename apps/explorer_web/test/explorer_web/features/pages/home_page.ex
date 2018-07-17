defmodule ExplorerWeb.HomePage do
  @moduledoc false

  use Wallaby.DSL

  import Wallaby.Query, only: [css: 1, css: 2]

  alias Explorer.Chain.{InternalTransaction, Transaction}

  def blocks(count: count) do
    css("[data-test='chain_block']", count: count)
  end

  def contract_creation(%InternalTransaction{created_contract_address_hash: hash}) do
    css("[data-test='contract-creation'] [data-address-hash='#{hash}']")
  end

  def search(session, text) do
    session
    |> fill_in(css("[data-test='search_input']"), with: text)
    |> send_keys([:enter])
  end

  def transactions(count: count) do
    css("[data-test='chain_transaction']", count: count)
  end

  def transaction_status(%Transaction{hash: transaction_hash}) do
    css("[data-transaction-hash='#{transaction_hash}'] [data-test='transaction_status']")
  end

  def visit_page(session) do
    visit(session, "/")
  end
end
