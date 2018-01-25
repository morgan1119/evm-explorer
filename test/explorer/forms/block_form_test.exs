defmodule Explorer.BlockFormTest do
  use Explorer.DataCase
  alias Explorer.BlockForm

  describe "build/1" do
    test "that it works" do
      block = insert(:block)
      assert BlockForm.build(block)
    end

    test "that it has a number" do
      block = insert(:block, number: 311)
      insert_list(2, :transaction, block: block)
      assert BlockForm.build(block).number == 311
    end

    test "that it returns a count of transactions" do
      block = insert(:block, number: 311)
      insert_list(2, :transaction, block: block)
      assert BlockForm.build(block).transactions_count == 2
    end

    test "that it returns a block's age" do
      block = insert(:block, timestamp: Timex.now |> Timex.shift(hours: -1))
      assert BlockForm.build(block).age == "1 hour ago"
    end
  end
end
