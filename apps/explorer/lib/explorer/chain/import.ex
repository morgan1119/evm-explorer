defmodule Explorer.Chain.Import do
  @moduledoc """
  Bulk importing of data into `Explorer.Repo`
  """

  alias Ecto.{Changeset, Multi}
  alias Explorer.Chain.Import
  alias Explorer.Repo

  # in order so that foreign keys are inserted before being referenced
  @runners [
    Import.Addresses,
    Import.Address.CoinBalances,
    Import.Blocks,
    Import.Block.SecondDegreeRelations,
    Import.Transactions,
    Import.Transaction.Forks,
    Import.InternalTransactions,
    Import.Logs,
    Import.Tokens,
    Import.TokenTransfers,
    Import.Address.TokenBalances
  ]

  quoted_runner_option_value =
    quote do
      Import.Runner.options()
    end

  quoted_runner_options =
    for runner <- @runners do
      quoted_key =
        quote do
          optional(unquote(runner.option_key()))
        end

      {quoted_key, quoted_runner_option_value}
    end

  @type all_options :: %{
          optional(:broadcast) => boolean,
          optional(:timeout) => timeout,
          unquote_splicing(quoted_runner_options)
        }

  quoted_runner_imported =
    for runner <- @runners do
      quoted_key =
        quote do
          optional(unquote(runner.option_key()))
        end

      quoted_value =
        quote do
          unquote(runner).imported()
        end

      {quoted_key, quoted_value}
    end

  @type all_result ::
          {:ok, %{unquote_splicing(quoted_runner_imported)}}
          | {:error, [Changeset.t()]}
          | {:error, step :: Ecto.Multi.name(), failed_value :: any(),
             changes_so_far :: %{optional(Ecto.Multi.name()) => any()}}

  @type timestamps :: %{inserted_at: DateTime.t(), updated_at: DateTime.t()}

  # milliseconds
  @transaction_timeout 120_000

  @imported_table_rows @runners
                       |> Stream.map(&Map.put(&1.imported_table_row(), :key, &1.option_key()))
                       |> Enum.map_join("\n", fn %{
                                                   key: key,
                                                   value_type: value_type,
                                                   value_description: value_description
                                                 } ->
                         "| `#{inspect(key)}` | `#{value_type}` | #{value_description} |"
                       end)
  @runner_options_doc Enum.map_join(@runners, fn runner ->
                        ecto_schema_module = runner.ecto_schema_module()

                        """
                          * `#{runner.option_key() |> inspect()}`
                            * `:on_conflict` - what to do if a conflict occurs with a pre-existing row: `:nothing`, `:replace_all`, or an
                              `t:Ecto.Query.t/0` to update specific columns.
                            * `:params` - `list` of params for changeset function in `#{ecto_schema_module}`.
                            * `:with` - changeset function to use in `#{ecto_schema_module}`.  Default to `:changeset`.
                            * `:timeout` - the timeout for inserting each batch of changes from `:params`.
                              Defaults to `#{runner.timeout()}` milliseconds.
                        """
                      end)

  @doc """
  Bulk insert all data stored in the `Explorer`.

  The import returns the unique key(s) for each type of record inserted.

  | Key | Value Type | Value Description |
  |-----|------------|-------------------|
  #{@imported_table_rows}

  The params for each key are validated using the corresponding `Ecto.Schema` module's `changeset/2` function.  If there
  are errors, they are returned in `Ecto.Changeset.t`s, so that the original, invalid value can be reconstructed for any
  error messages.

  Because there are multiple processes potentially writing to the same tables at the same time,
  `c:Ecto.Repo.insert_all/2`'s
  [`:conflict_target` and `:on_conflict` options](https://hexdocs.pm/ecto/Ecto.Repo.html#c:insert_all/3-options) are
  used to perform [upserts](https://hexdocs.pm/ecto/Ecto.Repo.html#c:insert_all/3-upserts) on all tables, so that
  a pre-existing unique key will not trigger a failure, but instead replace or otherwise update the row.

  ## Data Notifications

  On successful inserts, processes interested in certain domains of data will be notified
  that new data has been inserted. See `Explorer.Chain.subscribe_to_events/1` for more information.

  ## Options

    * `:broadcast` - Boolean flag indicating whether or not to broadcast the event.
    * `:timeout` - the timeout for the whole `c:Ecto.Repo.transaction/0` call.  Defaults to `#{@transaction_timeout}`
      milliseconds.
  #{@runner_options_doc}
  """
  @spec all(all_options()) :: all_result()
  def all(options) when is_map(options) do
    with {:ok, runner_options_pairs} <- validate_options(options),
         {:ok, valid_runner_option_pairs} <- validate_runner_options_pairs(runner_options_pairs),
         {:ok, runner_changes_list_pairs} <- runner_changes_list_pairs(valid_runner_option_pairs),
         {:ok, data} <- insert_runner_changes_list_pairs(runner_changes_list_pairs, options) do
      broadcast_events(data, Map.get(options, :broadcast, false))
      {:ok, data}
    end
  end

  defp broadcast_events(_data, false), do: nil

  defp broadcast_events(data, broadcast_type) do
    for {event_type, event_data} <- data,
        event_type in ~w(addresses address_coin_balances blocks internal_transactions logs token_transfers transactions)a do
      broadcast_event_data(event_type, broadcast_type, event_data)
    end
  end

  defp broadcast_event_data(event_type, broadcast_type, event_data) do
    Registry.dispatch(Registry.ChainEvents, event_type, fn entries ->
      for {pid, _registered_val} <- entries do
        send(pid, {:chain_event, event_type, broadcast_type, event_data})
      end
    end)
  end

  defp runner_changes_list_pairs(runner_options_pairs) when is_list(runner_options_pairs) do
    {status, reversed} =
      runner_options_pairs
      |> Stream.map(fn {runner, options} -> runner_changes_list(runner, options) end)
      |> Enum.reduce({:ok, []}, fn
        {:ok, runner_changes_pair}, {:ok, acc_runner_changes_pairs} ->
          {:ok, [runner_changes_pair | acc_runner_changes_pairs]}

        {:ok, _}, {:error, _} = error ->
          error

        {:error, _} = error, {:ok, _} ->
          error

        {:error, runner_changesets}, {:error, acc_changesets} ->
          {:error, acc_changesets ++ runner_changesets}
      end)

    {status, Enum.reverse(reversed)}
  end

  defp runner_changes_list(runner, %{params: params} = options) do
    ecto_schema_module = runner.ecto_schema_module()
    changeset_function_name = Map.get(options, :with, :changeset)
    struct = ecto_schema_module.__struct__()

    params
    |> Stream.map(&apply(ecto_schema_module, changeset_function_name, [struct, &1]))
    |> Enum.reduce({:ok, []}, fn
      changeset = %Changeset{valid?: false}, {:ok, _} ->
        {:error, [changeset]}

      changeset = %Changeset{valid?: false}, {:error, acc_changesets} ->
        {:error, [changeset | acc_changesets]}

      %Changeset{changes: changes, valid?: true}, {:ok, acc_changes} ->
        {:ok, [changes | acc_changes]}

      %Changeset{valid?: true}, {:error, _} = error ->
        error
    end)
    |> case do
      {:ok, changes} -> {:ok, {runner, changes}}
      {:error, _} = error -> error
    end
  end

  @global_options ~w(broadcast timeout)a

  defp validate_options(options) when is_map(options) do
    local_options = Map.drop(options, @global_options)

    {reverse_runner_options_pairs, unknown_options} =
      Enum.reduce(@runners, {[], local_options}, fn runner, {acc_runner_options_pairs, unknown_options} = acc ->
        option_key = runner.option_key()

        case local_options do
          %{^option_key => option_value} ->
            {[{runner, option_value} | acc_runner_options_pairs], Map.delete(unknown_options, option_key)}

          _ ->
            acc
        end
      end)

    case Enum.empty?(unknown_options) do
      true -> {:ok, Enum.reverse(reverse_runner_options_pairs)}
      false -> {:error, {:unknown_options, unknown_options}}
    end
  end

  defp validate_runner_options_pairs(runner_options_pairs) when is_list(runner_options_pairs) do
    {status, reversed} =
      runner_options_pairs
      |> Stream.map(fn {runner, options} -> validate_runner_options(runner, options) end)
      |> Enum.reduce({:ok, []}, fn
        :ignore, acc ->
          acc

        {:ok, valid_runner_option_pair}, {:ok, valid_runner_options_pairs} ->
          {:ok, [valid_runner_option_pair | valid_runner_options_pairs]}

        {:ok, _}, {:error, _} = error ->
          error

        {:error, reason}, {:ok, _} ->
          {:error, [reason]}

        {:error, reason}, {:error, reasons} ->
          {:error, [reason | reasons]}
      end)

    {status, Enum.reverse(reversed)}
  end

  defp validate_runner_options(runner, options) when is_map(options) do
    option_key = runner.option_key()

    case {validate_runner_option_params_required(option_key, options),
          validate_runner_options_known(option_key, options)} do
      {:ignore, :ok} -> :ignore
      {:ignore, {:error, _} = error} -> error
      {:ok, :ok} -> {:ok, {runner, options}}
      {:ok, {:error, _} = error} -> error
      {{:error, reason}, :ok} -> {:error, [reason]}
      {{:error, reason}, {:error, reasons}} -> {:error, [reason | reasons]}
    end
  end

  defp validate_runner_option_params_required(_, %{params: params}) do
    case Enum.empty?(params) do
      false -> :ok
      true -> :ignore
    end
  end

  defp validate_runner_option_params_required(runner_option_key, _),
    do: {:error, {:required, [runner_option_key, :params]}}

  @local_options ~w(on_conflict params with timeout)a

  defp validate_runner_options_known(runner_option_key, options) do
    unknown_option_keys = Map.keys(options) -- @local_options

    if Enum.empty?(unknown_option_keys) do
      :ok
    else
      reasons = Enum.map(unknown_option_keys, &{:unknown, [runner_option_key, &1]})

      {:error, reasons}
    end
  end

  defp runner_changes_list_pairs_to_multi(runner_changes_list_pairs, options)
       when is_list(runner_changes_list_pairs) and is_map(options) do
    timestamps = timestamps()
    full_options = Map.put(options, :timestamps, timestamps)

    Enum.reduce(runner_changes_list_pairs, Multi.new(), fn {runner, changes_list}, acc ->
      runner.run(acc, changes_list, full_options)
    end)
  end

  def insert_changes_list(changes_list, options) when is_list(changes_list) do
    ecto_schema_module = Keyword.fetch!(options, :for)

    timestamped_changes_list = timestamp_changes_list(changes_list, Keyword.fetch!(options, :timestamps))

    {_, inserted} =
      Repo.safe_insert_all(
        ecto_schema_module,
        timestamped_changes_list,
        Keyword.delete(options, :for)
      )

    {:ok, inserted}
  end

  defp timestamp_changes_list(changes_list, timestamps) when is_list(changes_list) do
    Enum.map(changes_list, &timestamp_params(&1, timestamps))
  end

  defp timestamp_params(changes, timestamps) when is_map(changes) do
    Map.merge(changes, timestamps)
  end

  defp import_transaction(multi, options) when is_map(options) do
    Repo.transaction(multi, timeout: Map.get(options, :timeout, @transaction_timeout))
  end

  defp insert_runner_changes_list_pairs(runner_changes_list_pairs, options) do
    runner_changes_list_pairs
    |> runner_changes_list_pairs_to_multi(options)
    |> import_transaction(options)
  end

  @spec timestamps() :: timestamps
  defp timestamps do
    now = DateTime.utc_now()
    %{inserted_at: now, updated_at: now}
  end
end
