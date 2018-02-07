defmodule Explorer.BlockImporter do
  @moduledoc "Imports a block."

  import Ethereumex.HttpClient, only: [eth_get_block_by_number: 2]

  alias Explorer.Block
  alias Explorer.Repo.NewRelic, as: Repo
  alias Explorer.Workers.ImportTransaction

  @dialyzer {:nowarn_function, import: 1}
  def import(block_number) do
    raw_block = download_block(block_number)
    changes = extract_block(raw_block)

    block = Repo.get_by(Block, hash: changes.hash) || %Block{}
    block
    |> Block.changeset(changes)
    |> Repo.insert_or_update!

    import_transactions(raw_block["transactions"])
  end

  @dialyzer {:nowarn_function, download_block: 1}
  def download_block(block_number) do
    {:ok, block} = eth_get_block_by_number(block_number, false)
    block
  end

  def extract_block(raw_block) do
    %{
      hash: raw_block["hash"],
      number: raw_block["number"] |> decode_integer_field,
      gas_used: raw_block["gasUsed"] |> decode_integer_field,
      timestamp: raw_block["timestamp"] |> decode_time_field,
      parent_hash: raw_block["parentHash"],
      miner: raw_block["miner"],
      difficulty: raw_block["difficulty"] |> decode_integer_field,
      total_difficulty: raw_block["totalDifficulty"] |> decode_integer_field,
      size: raw_block["size"] |> decode_integer_field,
      gas_limit: raw_block["gasLimit"] |> decode_integer_field,
      nonce: raw_block["nonce"] || "0",
    }
  end

  def import_transactions(transactions) do
    Enum.map(transactions, fn (transaction) ->
      ImportTransaction.perform_later(transaction)
    end)
  end

  def decode_integer_field(hex) do
    {"0x", base_16} = String.split_at(hex, 2)
    String.to_integer(base_16, 16)
  end

  def decode_time_field(field) do
    field |> decode_integer_field |> Timex.from_unix
  end
end
