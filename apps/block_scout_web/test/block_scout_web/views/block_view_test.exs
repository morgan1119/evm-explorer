defmodule BlockScoutWeb.BlockViewTest do
  use BlockScoutWeb.ConnCase, async: true

  alias BlockScoutWeb.BlockView
  alias Explorer.Repo

  describe "average_gas_price/1" do
    test "returns an average of the gas prices for a block's transactions with the unit value" do
      block = insert(:block)

      Enum.each(1..10, fn index ->
        :transaction
        |> insert(gas_price: 10_000_000_000 * index)
        |> with_block(block)
      end)

      assert "55 Gwei" == BlockView.average_gas_price(Repo.preload(block, [:transactions]))
    end
  end

  describe "formatted_timestamp/1" do
    test "returns a formatted timestamp string for a block" do
      block = insert(:block)

      assert Timex.format!(block.timestamp, "%b-%d-%Y %H:%M:%S %p %Z", :strftime) ==
               BlockView.formatted_timestamp(block)
    end
  end

  describe "uncle?/1" do
    test "returns true for an uncle block" do
      uncle = insert(:block, consensus: false)

      assert BlockView.uncle?(uncle)
    end

    test "returns false for a block" do
      block = insert(:block)

      refute BlockView.uncle?(block)
    end
  end
end
