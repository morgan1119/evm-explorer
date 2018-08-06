defmodule Explorer.Chain.StatisticsTest do
  use Explorer.DataCase

  alias Explorer.Chain.Statistics
  alias Timex.Duration

  describe "fetch/0" do
    test "returns -1 for the number when there are no blocks" do
      assert %Statistics{number: -1} = Statistics.fetch()
    end

    test "returns the highest block number when there is a block" do
      insert(:block, number: 1)

      max_number = 100
      insert(:block, number: max_number)

      assert %Statistics{number: ^max_number} = Statistics.fetch()
    end

    test "returns the latest block timestamp" do
      time = DateTime.utc_now()
      insert(:block, timestamp: time)

      statistics = Statistics.fetch()

      assert Timex.diff(statistics.timestamp, time, :seconds) == 0
    end

    test "returns the average time between blocks for the last 100 blocks" do
      time = DateTime.utc_now()

      insert(:block, timestamp: Timex.shift(time, seconds: -1000))

      for x <- 100..0 do
        insert(:block, timestamp: Timex.shift(time, seconds: -5 * x))
      end

      assert %Statistics{
               average_time: %Duration{
                 seconds: 5,
                 megaseconds: 0,
                 microseconds: 0
               }
             } = Statistics.fetch()
    end

    test "returns the last five blocks" do
      insert_list(5, :block)

      statistics = Statistics.fetch()

      assert statistics.blocks |> Enum.count() == 4
    end

    test "returns the last five transactions with blocks" do
      Enum.map(0..5, fn _ ->
        :transaction
        |> insert()
        |> with_block()
      end)

      statistics = Statistics.fetch()

      assert statistics.transactions |> Enum.count() == 5
    end
  end
end
