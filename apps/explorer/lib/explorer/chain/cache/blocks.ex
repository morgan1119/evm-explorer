defmodule Explorer.Chain.Cache.Blocks do
  @moduledoc """
  Caches the last imported blocks
  """

  alias Explorer.Chain.Block

  use Explorer.Chain.OrderedCache,
    name: :blocks,
    max_size: 60,
    ids_list_key: "block_numbers",
    preload: :transactions,
    preload: [miner: :names],
    preload: :rewards,
    ttl_check_interval: Application.get_env(:explorer, __MODULE__)[:ttl_check_interval],
    global_ttl: Application.get_env(:explorer, __MODULE__)[:global_ttl]

  @type element :: Block.t()

  @type id :: non_neg_integer()

  def element_to_id(%Block{number: number}), do: number
end
