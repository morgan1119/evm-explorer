defmodule Explorer.BlockImporter do
  @moduledoc "Imports a block."

  import Ecto.Query
  import Ethereumex.HttpClient, only: [eth_get_block_by_number: 2]

  alias Explorer.Block
  alias Explorer.Repo.NewRelic, as: Repo
  alias Explorer.Workers.ImportTransaction

  @dialyzer {:nowarn_function, import: 1}
  def import("pending") do
    raw_block = download_block("pending")
    Enum.map(raw_block["transactions"], &ImportTransaction.perform_later/1)
  end

  @dialyzer {:nowarn_function, import: 1}
  def import(block_number) do
    raw_block = download_block(block_number)
    changes = extract_block(raw_block)
    block = changes.hash |> find()

    if is_nil(block.id), do: block |> Block.changeset(changes) |> Repo.insert

    Enum.map(raw_block["transactions"], &ImportTransaction.perform/1)
  end

  def find(hash) do
    query = from b in Block,
      where: fragment("lower(?)", b.hash) == ^String.downcase(hash),
      limit: 1
    (query |> Repo.one()) || %Block{}
  end

  @dialyzer {:nowarn_function, download_block: 1}
  def download_block(block_number) do
    {:ok, block} = eth_get_block_by_number(block_number, true)
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

  def decode_integer_field(hex) do
    {"0x", base_16} = String.split_at(hex, 2)
    String.to_integer(base_16, 16)
  end

  def decode_time_field(field) do
    field |> decode_integer_field |> Timex.from_unix
  end
end
