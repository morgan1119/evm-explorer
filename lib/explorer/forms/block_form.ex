defmodule Explorer.BlockForm do
  import Ecto.Query
  alias Explorer.Transaction
  alias Explorer.Repo

  @moduledoc false

  def build(block) do
    block |> Map.merge(%{
      transactions_count: block |> get_transactions_count,
      age: block |> calculate_age,
      formatted_timestamp: block |> format_timestamp,
    })
  end

  def get_transactions_count(block) do
    Transaction
      |> where([t], t.block_id == ^block.id)
      |> Repo.all
      |> Enum.count
  end

  def calculate_age(block) do
    block.timestamp |> Timex.from_now
  end

  def format_timestamp(block) do
    block.timestamp |> Timex.format!("%b-%d-%Y %H:%M:%S %p %Z", :strftime)
  end
end
