defmodule ExplorerWeb.TransactionLogsPage do
  @moduledoc false

  use Wallaby.DSL

  import Wallaby.Query, only: [css: 1, css: 2]
  import ExplorerWeb.Router.Helpers, only: [transaction_log_path: 4]

  alias Explorer.Chain.{Address, Transaction}
  alias ExplorerWeb.Endpoint

  def logs(count: count) do
    css("[data-test='transaction_log']", count: count)
  end

  def visit_page(session, %Transaction{} = transaction) do
    visit(session, transaction_log_path(Endpoint, :index, :en, transaction))
  end

  def click_address(session, %Address{hash: address_hash}) do
    click(session, css("[data-test='log_address_link'][data-address-hash='#{address_hash}']"))
  end
end
