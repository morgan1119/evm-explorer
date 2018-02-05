defmodule ExplorerWeb.ChainController do
  alias Explorer.Block
  alias Explorer.Transaction
  alias Explorer.Repo

  import Ecto.Query

  use ExplorerWeb, :controller

  def show(conn, _params) do
    blocks = from b in Block,
      order_by: [desc: b.number],
      preload: :transactions,
      limit: 5

    transactions = from t in Transaction,
      join: b in Block, on: b.id == t.block_id,
      order_by: [desc: b.number],
      preload: :block,
      limit: 5

    render(
      conn,
      "show.html",
      blocks: Repo.all(blocks),
      transactions: Repo.all(transactions)
    )
  end
end
