defmodule ExplorerWeb.TransactionControllerTest do
  use ExplorerWeb.ConnCase

  import ExplorerWeb.Router.Helpers, only: [transaction_path: 4]

  describe "GET index/2" do
    test "returns a transaction with a receipt", %{conn: conn} do
      transaction = insert(:transaction)
      block = insert(:block)
      insert(:receipt, transaction: transaction)
      insert(:block_transaction, transaction: transaction, block: block)
      conn = get(conn, "/en/transactions")
      assert List.first(conn.assigns.transactions.entries).id == transaction.id
    end

    test "returns a count of transactions", %{conn: conn} do
      transaction = insert(:transaction)
      block = insert(:block)
      insert(:receipt, transaction: transaction)
      insert(:block_transaction, transaction: transaction, block: block)

      conn = get(conn, "/en/transactions")

      assert length(conn.assigns.transactions.entries) === 1
    end

    test "returns no pending transactions", %{conn: conn} do
      insert(:transaction) |> with_block()
      conn = get(conn, "/en/transactions")
      assert conn.assigns.transactions.entries == []
    end

    test "only returns transactions that have a receipt", %{conn: conn} do
      insert(:transaction)
      conn = get(conn, "/en/transactions")
      assert length(conn.assigns.transactions.entries) === 0
    end

    test "paginates transactions using the last seen transaction", %{conn: conn} do
      transaction = insert(:transaction)
      block = insert(:block)
      insert(:receipt, transaction: transaction)
      insert(:block_transaction, transaction: transaction, block: block)
      conn = get(conn, "/en/transactions", last_seen: transaction.id)
      assert conn.assigns.transactions.entries == []
    end

    test "sends back an estimate of the number of transactions", %{conn: conn} do
      insert(:transaction)
      conn = get(conn, "/en/transactions")
      refute conn.assigns.transactions.total_entries == nil
    end

    test "works when there are no transactions", %{conn: conn} do
      conn = get(conn, "/en/transactions")
      assert conn.assigns.transactions.total_entries == 0
      assert conn.assigns.transactions.entries == []
    end
  end

  describe "GET show/3" do
    test "without transaction", %{conn: conn} do
      conn = get(conn, "/en/transactions/0x1")

      assert html_response(conn, 404)
    end

    test "when there is an associated block, it returns a transaction with block data", %{
      conn: conn
    } do
      block = insert(:block, %{number: 777})
      transaction = insert(:transaction, hash: "0x8") |> with_block(block)

      conn = get(conn, "/en/transactions/0x8")

      assert html = html_response(conn, 200)

      assert html |> Floki.find("div.transaction__header h3") |> Floki.text() == transaction.hash

      assert html |> Floki.find("span.transaction__item--primary a") |> Floki.text() == to_string(block.number)
    end

    test "returns a transaction without associated block data", %{conn: conn} do
      transaction = insert(:transaction, hash: "0x8")

      conn = get(conn, "/en/transactions/0x8")

      assert html = html_response(conn, 200)

      assert html |> Floki.find("div.transaction__header h3") |> Floki.text() == transaction.hash
      assert html |> Floki.find("span.transaction__item--primary a") |> Floki.text() == ""
    end

    test "returns internal transactions for the transaction", %{conn: conn} do
      transaction = insert(:transaction)
      expected_internal_transaction = insert(:internal_transaction, transaction_id: transaction.id, index: 0)
      insert(:internal_transaction, transaction_id: transaction.id, index: 1)

      path = transaction_path(ExplorerWeb.Endpoint, :show, :en, transaction.hash)

      conn = get(conn, path)

      actual_internal_transaction_ids =
        conn.assigns.internal_transactions.entries
        |> Enum.map(fn it -> it.id end)

      assert conn.assigns.transaction.hash == transaction.hash
      assert Enum.member?(actual_internal_transaction_ids, expected_internal_transaction.id)
    end
  end
end
