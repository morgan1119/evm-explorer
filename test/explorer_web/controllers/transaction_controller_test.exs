defmodule ExplorerWeb.TransactionControllerTest do
  use ExplorerWeb.ConnCase

  describe "GET index/2" do
    test "returns a transaction with a receipt", %{conn: conn} do
      transaction = insert(:transaction)
      block = insert(:block)
      insert(:transaction_receipt, transaction: transaction)
      insert(:block_transaction, transaction: transaction, block: block)
      conn = get(conn, "/en/transactions")
      assert List.first(conn.assigns.transactions.entries).id == transaction.id
    end

    test "returns no pending transactions", %{conn: conn} do
      insert(:transaction)
      conn = get(conn, "/en/transactions")
      assert conn.assigns.transactions |> Enum.count === 0
    end
  end

  describe "GET show/3" do
    test "when there is an associated block, it returns a transaction with block data", %{conn: conn} do
      block = insert(:block, %{number: 777})
      transaction = insert(:transaction, hash: "0x8") |> with_block(block) |> with_addresses
      conn = get(conn, "/en/transactions/0x8")
      assert conn.assigns.transaction.id == transaction.id
      assert conn.assigns.transaction.block_number == block.number
    end

    test "returns a transaction without associated block data", %{conn: conn} do
      transaction = insert(:transaction, hash: "0x8") |> with_addresses
      conn = get(conn, "/en/transactions/0x8")
      assert conn.assigns.transaction.id == transaction.id
      assert conn.assigns.transaction.block_number == ""
    end
  end
end
