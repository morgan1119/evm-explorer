defmodule ExplorerWeb.AddressTransactionControllerTest do
  use ExplorerWeb.ConnCase

  import ExplorerWeb.Router.Helpers, only: [address_transaction_path: 4]
  import ExplorerWeb.Factory

  describe "GET index/2" do
    test "with invalid address hash", %{conn: conn} do
      conn = get(conn, address_transaction_path(conn, :index, :en, "invalid_address"))

      assert html_response(conn, 404)
    end

    test "with valid address hash without address", %{conn: conn} do
      conn = get(conn, address_transaction_path(conn, :index, :en, "0x8bf38d4764929064f2d4d3a56520a76ab3df415b"))

      assert html_response(conn, 404)
    end

    test "returns transactions for the address", %{conn: conn} do
      address = insert(:address)

      block = insert(:block)

      from_transaction =
        :transaction
        |> insert(block_hash: block.hash, from_address_hash: address.hash, index: 0)
        |> with_receipt()

      to_transaction =
        :transaction
        |> insert(block_hash: block.hash, to_address_hash: address.hash, index: 1)
        |> with_receipt()

      conn = get(conn, address_transaction_path(conn, :index, :en, address))

      actual_transaction_hashes =
        conn.assigns.page
        |> Enum.map(fn transaction -> transaction.hash end)

      assert html_response(conn, 200)
      assert Enum.member?(actual_transaction_hashes, from_transaction.hash)
      assert Enum.member?(actual_transaction_hashes, to_transaction.hash)
    end

    test "does not return related transactions without a receipt", %{conn: conn} do
      address = insert(:address)
      block = insert(:block)

      insert(
        :transaction,
        block_hash: block.hash,
        from_address_hash: address.hash,
        index: 0,
        to_address_hash: address.hash
      )

      conn = get(conn, address_transaction_path(ExplorerWeb.Endpoint, :index, :en, address))

      assert html_response(conn, 200)
      assert Enum.empty?(conn.assigns.page)
    end
  end
end
