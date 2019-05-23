defmodule Explorer.Chain.Import.Runner.StakingPools do
  @moduledoc """
  Bulk imports staking pools to StakingPool tabe.
  """

  require Ecto.Query

  alias Ecto.{Changeset, Multi, Repo}
  alias Explorer.Chain.{Import, StakingPool, Wei}

  import Ecto.Query, only: [from: 2]

  @behaviour Import.Runner

  # milliseconds
  @timeout 60_000

  @type imported :: [StakingPool.t()]

  @impl Import.Runner
  def ecto_schema_module, do: StakingPool

  @impl Import.Runner
  def option_key, do: :staking_pools

  @impl Import.Runner
  def imported_table_row do
    %{
      value_type: "[#{ecto_schema_module()}.t()]",
      value_description: "List of `t:#{ecto_schema_module()}.t/0`s"
    }
  end

  @impl Import.Runner
  def run(multi, changes_list, %{timestamps: timestamps} = options) do
    insert_options =
      options
      |> Map.get(option_key(), %{})
      |> Map.take(~w(on_conflict timeout)a)
      |> Map.put_new(:timeout, @timeout)
      |> Map.put(:timestamps, timestamps)

    multi
    |> Multi.run(:mark_as_deleted, fn repo, _ ->
      mark_as_deleted(repo, changes_list, insert_options)
    end)
    |> Multi.run(:insert_staking_pools, fn repo, _ ->
      insert(repo, changes_list, insert_options)
    end)
  end

  @impl Import.Runner
  def timeout, do: @timeout

  defp mark_as_deleted(repo, changes_list, %{timeout: timeout}) when is_list(changes_list) do
    addresses = Enum.map(changes_list, & &1.staking_address_hash)

    query =
      from(
        pool in StakingPool,
        where: pool.staking_address_hash not in ^addresses,
        update: [
          set: [
            is_deleted: true
          ]
        ]
      )

    try do
      {_, result} = repo.update_all(query, [], timeout: timeout)

      {:ok, result}
    rescue
      postgrex_error in Postgrex.Error ->
        {:error, %{exception: postgrex_error}}
    end
  end

  @spec insert(Repo.t(), [map()], %{
          optional(:on_conflict) => Import.Runner.on_conflict(),
          required(:timeout) => timeout,
          required(:timestamps) => Import.timestamps()
        }) ::
          {:ok, [StakingPool.t()]}
          | {:error, [Changeset.t()]}
  defp insert(repo, changes_list, %{timeout: timeout, timestamps: timestamps} = options) when is_list(changes_list) do
    on_conflict = Map.get_lazy(options, :on_conflict, &default_on_conflict/0)

    {:ok, _} =
      Import.insert_changes_list(
        repo,
        stakes_ratio(changes_list),
        conflict_target: :staking_address_hash,
        on_conflict: on_conflict,
        for: StakingPool,
        returning: [:staking_address_hash],
        timeout: timeout,
        timestamps: timestamps
      )
  end

  defp default_on_conflict do
    from(
      name in StakingPool,
      update: [
        set: [
          mining_address_hash: fragment("EXCLUDED.mining_address_hash"),
          delegators_count: fragment("EXCLUDED.delegators_count"),
          is_active: fragment("EXCLUDED.is_active"),
          is_banned: fragment("EXCLUDED.is_banned"),
          is_validator: fragment("EXCLUDED.is_validator"),
          likelihood: fragment("EXCLUDED.likelihood"),
          staked_ratio: fragment("EXCLUDED.staked_ratio"),
          min_candidate_stake: fragment("EXCLUDED.min_candidate_stake"),
          min_delegator_stake: fragment("EXCLUDED.min_delegator_stake"),
          self_staked_amount: fragment("EXCLUDED.self_staked_amount"),
          staked_amount: fragment("EXCLUDED.staked_amount"),
          was_banned_count: fragment("EXCLUDED.was_banned_count"),
          was_validator_count: fragment("EXCLUDED.was_validator_count"),
          is_deleted: fragment("EXCLUDED.is_deleted"),
          inserted_at: fragment("LEAST(?, EXCLUDED.inserted_at)", name.inserted_at),
          updated_at: fragment("GREATEST(?, EXCLUDED.updated_at)", name.updated_at)
        ]
      ]
    )
  end

  # Calculates staked ratio for each pool
  defp stakes_ratio(pools) do
    active_pools = Enum.filter(pools, & &1.is_active)

    stakes_total =
      pools
      |> Enum.reduce(0, fn pool, acc ->
        acc + Wei.to(pool.staked_amount, :integer)
      end)

    Enum.map(active_pools, fn pool ->
      staked_ratio = if stakes_total > 0, do: Wei.to(pool.staked_amount, :integer) / stakes_total, else: 0

      Map.put(pool, :staked_ratio, staked_ratio)
    end)
  end
end
