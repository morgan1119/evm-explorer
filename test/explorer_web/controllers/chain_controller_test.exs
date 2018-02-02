defmodule ExplorerWeb.ChainControllerTest do
  use ExplorerWeb.ConnCase

  def build_transaction(block \\ nil) do
    block = block || insert(:block)
    transaction = insert(:transaction, block: block)
    to_address = insert(:address)
    from_address = insert(:address)
    insert(:to_address, transaction: transaction, address: to_address)
    insert(:from_address, transaction: transaction, address: from_address)
  end

  describe "GET index/2 without a locale" do
    test "redirects to the en locale", %{conn: conn} do
      conn = get conn, "/"
      assert redirected_to(conn) == "/en"
    end
  end

  describe "GET index/2 with a locale" do
    test "returns a welcome message", %{conn: conn} do
      conn = get conn, ExplorerWeb.Router.Helpers.chain_path(ExplorerWeb.Endpoint, :show, %{locale: :en})
      assert html_response(conn, 200) =~ "POA"
    end

    test "returns a block", %{conn: conn} do
      insert(:block, %{number: 23})
      conn = get conn, "/en"

      assert(List.first(conn.assigns.blocks).number == 23)
    end

    test "excludes all but the most recent five blocks", %{conn: conn} do
      old_block = insert(:block)
      insert_list(5, :block)
      conn = get conn, "/en"
      refute(Enum.member?(conn.assigns.blocks, old_block))
    end

    test "returns a transaction", %{conn: conn} do
      block = insert(:block, number: 33)
      insert(:transaction, hash: "0xDECAFBAD", block: block) |> with_addresses(%{to: "0xsleepypuppy", from: "0xilovefrogs"})

      conn = get conn, "/en"

      assert(List.first(conn.assigns.transactions).hash == "0xDECAFBAD")
      assert(List.first(conn.assigns.transactions).block.number == 33)
    end

    test "returns only the five most recent transactions", %{conn: conn} do
      block_mined_today = insert(:block, timestamp: Timex.now |> Timex.shift(hours: -1))
      insert(:transaction, hash: "0xStuff", inserted_at: Timex.now |> Timex.shift(hours: -1), block: block_mined_today) |> with_addresses

      block_mined_last_week = insert(:block, timestamp: Timex.now |> Timex.shift(weeks: -1))
      for _ <- 0..4, do: insert(:transaction, %{block: block_mined_last_week}) |> with_addresses

      conn = get conn, "/en"

      assert Enum.count(conn.assigns.transactions) == 5
      assert List.first(conn.assigns.transactions).hash == "0xStuff"
    end
  end
end
