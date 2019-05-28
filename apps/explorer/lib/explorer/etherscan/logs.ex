defmodule Explorer.Etherscan.Logs do
  @moduledoc """
  This module contains functions for working with logs, as they pertain to the
  `Explorer.Etherscan` context.

  """

  import Ecto.Query, only: [from: 2, where: 3, subquery: 1]

  alias Explorer.Chain.{Block, InternalTransaction, Log, Transaction}
  alias Explorer.Repo

  @base_filter %{
    from_block: nil,
    to_block: nil,
    address_hash: nil,
    first_topic: nil,
    second_topic: nil,
    third_topic: nil,
    fourth_topic: nil,
    topic0_1_opr: nil,
    topic0_2_opr: nil,
    topic0_3_opr: nil,
    topic1_2_opr: nil,
    topic1_3_opr: nil,
    topic2_3_opr: nil
  }

  @log_fields [
    :data,
    :first_topic,
    :second_topic,
    :third_topic,
    :fourth_topic,
    :index,
    :address_hash,
    :transaction_hash
  ]

  @doc """
  Gets a list of logs that meet the criteria in a given filter map.

  Required filter parameters:

  * `from_block`
  * `to_block`
  * `address_hash` and/or `{x}_topic`
  * When multiple `{x}_topic` params are provided, then the corresponding
  `topic{x}_{x}_opr` param is required. For example, if "first_topic" and
  "second_topic" are provided, then "topic0_1_opr" is required.

  Supported `{x}_topic`s:

  * first_topic
  * second_topic
  * third_topic
  * fourth_topic

  Supported `topic{x}_{x}_opr`s:

  * topic0_1_opr
  * topic0_2_opr
  * topic0_3_opr
  * topic1_2_opr
  * topic1_3_opr
  * topic2_3_opr

  """
  @spec list_logs(map()) :: [map()]
  def list_logs(%{address_hash: address_hash} = filter) when not is_nil(address_hash) do
    prepared_filter = Map.merge(@base_filter, filter)

    logs_query = where_topic_match(Log, prepared_filter)

    internal_transaction_log_query =
      from(internal_transaction in InternalTransaction,
        join: transaction in assoc(internal_transaction, :transaction),
        join: log in ^logs_query,
        on: log.transaction_hash == internal_transaction.transaction_hash,
        where: internal_transaction.block_number >= ^prepared_filter.from_block,
        where: internal_transaction.block_number <= ^prepared_filter.to_block,
        where: internal_transaction.to_address_hash == ^address_hash,
        or_where: internal_transaction.from_address_hash == ^address_hash,
        or_where: internal_transaction.created_contract_address_hash == ^address_hash,
        select:
          merge(map(log, ^@log_fields), %{
            gas_price: transaction.gas_price,
            gas_used: transaction.gas_used,
            transaction_index: transaction.index,
            block_number: transaction.block_number
          })
      )

    all_transaction_logs_query =
      from(transaction in Transaction,
        join: log in ^logs_query,
        on: log.transaction_hash == transaction.hash,
        where: transaction.block_number >= ^prepared_filter.from_block,
        where: transaction.block_number <= ^prepared_filter.to_block,
        where: transaction.to_address_hash == ^address_hash,
        or_where: transaction.from_address_hash == ^address_hash,
        or_where: transaction.created_contract_address_hash == ^address_hash,
        select:
          merge(map(log, ^@log_fields), %{
            gas_price: transaction.gas_price,
            gas_used: transaction.gas_used,
            transaction_index: transaction.index,
            block_number: transaction.block_number
          }),
        union: ^internal_transaction_log_query
      )

    query_with_blocks =
      from(log_transaction_data in subquery(all_transaction_logs_query),
        join: block in Block,
        on: block.number == log_transaction_data.block_number,
        on: block.consensus == true,
        where: log_transaction_data.address_hash == ^address_hash,
        order_by: block.number,
        limit: 1000,
        select_merge: %{
          block_timestamp: block.timestamp
        }
      )

    Repo.all(query_with_blocks)
  end

  # Since address_hash was not present, we know that a
  # topic filter has been applied, and th
  def list_logs(filter) do
    prepared_filter = Map.merge(@base_filter, filter)

    logs_query = where_topic_match(Log, prepared_filter)

    block_transaction_query =
      from(transaction in Transaction,
        join: block in assoc(transaction, :block),
        on: block.number >= ^prepared_filter.from_block,
        on: block.number <= ^prepared_filter.to_block,
        on: block.consensus == true,
        select: %{
          transaction_hash: transaction.hash,
          gas_price: transaction.gas_price,
          gas_used: transaction.gas_used,
          transaction_index: transaction.index,
          block_number: block.number,
          block_timestamp: block.timestamp
        }
      )

    query_with_block_transaction_data =
      from(log in logs_query,
        join: block_transaction_data in subquery(block_transaction_query),
        on: block_transaction_data.transaction_hash == log.transaction_hash,
        order_by: block_transaction_data.block_number,
        limit: 1000,
        select: block_transaction_data,
        select_merge: map(log, ^@log_fields)
      )

    Repo.all(query_with_block_transaction_data)
  end

  @topics [
    :first_topic,
    :second_topic,
    :third_topic,
    :fourth_topic
  ]

  @topic_operations %{
    topic0_1_opr: {:first_topic, :second_topic},
    topic0_2_opr: {:first_topic, :third_topic},
    topic0_3_opr: {:first_topic, :fourth_topic},
    topic1_2_opr: {:second_topic, :third_topic},
    topic1_3_opr: {:second_topic, :fourth_topic},
    topic2_3_opr: {:third_topic, :fourth_topic}
  }

  defp where_topic_match(query, filter) do
    case Enum.filter(@topics, &filter[&1]) do
      [] ->
        query

      [topic] ->
        where(query, [l], field(l, ^topic) == ^filter[topic])

      _ ->
        where_multiple_topics_match(query, filter)
    end
  end

  defp where_multiple_topics_match(query, filter) do
    Enum.reduce(Map.keys(@topic_operations), query, fn topic_operation, acc_query ->
      where_multiple_topics_match(acc_query, filter, topic_operation, filter[topic_operation])
    end)
  end

  defp where_multiple_topics_match(query, filter, topic_operation, "and") do
    {topic_a, topic_b} = @topic_operations[topic_operation]
    where(query, [l], field(l, ^topic_a) == ^filter[topic_a] and field(l, ^topic_b) == ^filter[topic_b])
  end

  defp where_multiple_topics_match(query, filter, topic_operation, "or") do
    {topic_a, topic_b} = @topic_operations[topic_operation]
    where(query, [l], field(l, ^topic_a) == ^filter[topic_a] or field(l, ^topic_b) == ^filter[topic_b])
  end

  defp where_multiple_topics_match(query, _, _, _), do: query
end
