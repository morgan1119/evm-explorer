defmodule Explorer.Chain do
  @moduledoc """
  The chain context.
  """

  import Ecto.Query, only: [from: 2, order_by: 2, preload: 2, where: 2, where: 3]

  alias Ecto.Multi
  alias Explorer.Chain.{Address, Block, InternalTransaction, Log, Receipt, Transaction, Wei}
  alias Explorer.Repo

  # Types

  @typedoc """
  The name of an association on the `t:Ecto.Schema.t/0`
  """
  @type association :: atom()

  @typedoc """
  * `:optional` - the association is optional and only needs to be loaded if available
  * `:required` - the association is required and MUST be loaded.  If it is not available, then the parent struct
      SHOULD NOT be returned.
  """
  @type necessity :: :optional | :required

  @typedoc """
  The `t:necessity/0` of each association that should be loaded
  """
  @type necessity_by_association :: %{association => necessity}

  @typedoc """
  Pagination params used by `scrivener`
  """
  @type pagination :: map()

  @typep necessity_by_association_option :: {:necessity_by_association, necessity_by_association}
  @typep pagination_option :: {:pagination, pagination}

  # Functions

  def block_count do
    Repo.one(from(b in Block, select: count(b.id)))
  end

  @doc """
  Finds all `t:Explorer.Chain.Transaction.t/0` in the `t:Explorer.Chain.Block.t/0`.

  ## Options

  * `:necessity_by_association` - use to load `t:association/0` as `:required` or `:optional`.  If an association is
      `:required`, and the `t:Explorer.Chain.Transaction.t/0` has no associated record for that association, then the
      `t:Explorer.Chain.Transaction.t/0` will not be included in the page `entries`.
  * `:pagination` - pagination params to pass to scrivener.
  """
  @spec block_to_transactions(Block.t()) :: %Scrivener.Page{entries: [Transaction.t()]}
  @spec block_to_transactions(Block.t(), [necessity_by_association_option | pagination_option]) :: %Scrivener.Page{
          entries: [Transaction.t()]
        }
  def block_to_transactions(%Block{id: block_id}, options \\ []) when is_list(options) do
    necessity_by_association = Keyword.get(options, :necessity_by_association, %{})
    pagination = Keyword.get(options, :pagination, %{})

    query =
      from(
        transaction in Transaction,
        inner_join: block in assoc(transaction, :block),
        where: block.id == ^block_id,
        order_by: [desc: transaction.inserted_at]
      )

    query
    |> join_associations(necessity_by_association)
    |> Repo.paginate(pagination)
  end

  @doc """
  Counts the number of `t:Explorer.Chain.Transaction.t/0` in the `block`.
  """
  @spec block_to_transaction_count(Block.t()) :: non_neg_integer()
  def block_to_transaction_count(%Block{id: block_id}) do
    query =
      from(
        transaction in Transaction,
        where: transaction.block_id == ^block_id
      )

    Repo.aggregate(query, :count, :id)
  end

  @doc """
  How many blocks have confirmed `block` based on the current `max_block_number`
  """
  @spec confirmations(Block.t(), [{:max_block_number, Block.block_number()}]) :: non_neg_integer()
  def confirmations(%Block{number: number}, named_arguments) when is_list(named_arguments) do
    max_block_number = Keyword.fetch!(named_arguments, :max_block_number)

    max_block_number - number
  end

  @doc """
  Creates an address.

  ## Examples

      iex> Explorer.Addresses.create_address(%{field: value})
      {:ok, %Address{}}

      iex> Explorer.Addresses.create_address(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_address(map()) :: {:ok, Address.t()} | {:error, Ecto.Changeset.t()}
  def create_address(attrs \\ %{}) do
    %Address{}
    |> Address.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Ensures that an `t:Explorer.Address.t/0` exists with the given `hash`.

  If a `t:Explorer.Address.t/0` with `hash` already exists, it is returned

      iex> Explorer.Addresses.ensure_hash_address(existing_hash)
      {:ok, %Address{}}

  If a `t:Explorer.Address.t/0` does not exist with `hash`, it is created and returned

      iex> Explorer.Addresses.ensure_hash_address(new_hash)
      {:ok, %Address{}}

  There is a chance of a race condition when interacting with the database: the `t:Explorer.Address.t/0` may not exist
  when first checked, then already exist when it is tried to be created because another connection creates the addres,
  then another process deletes the address after this process's connection see it was created, but before it can be
  retrieved.  In scenario, the address may be not found as only one retry is attempted to prevent infinite loops.

      iex> Explorer.Addresses.ensure_hash_address(flicker_hash)
      {:error, :not_found}

  """
  @spec ensure_hash_address(Address.hash()) :: {:ok, Address.t()} | {:error, :not_found}
  def ensure_hash_address(hash) when is_binary(hash) do
    with {:error, :not_found} <- hash_to_address(hash),
         {:error, _} <- create_address(%{hash: hash}) do
      # assume race condition occurred and someone else created the address between the first
      # hash_to_address and create_address
      hash_to_address(hash)
    end
  end

  @doc """
  `t:Explorer.Chain.Transaction/0`s from `address`.

  ## Options

  * `:necessity_by_association` - use to load `t:association/0` as `:required` or `:optional`.  If an association is
      `:required`, and the `t:Explorer.Chain.Transaction.t/0` has no associated record for that association, then the
      `t:Explorer.Chain.Transaction.t/0` will not be included in the page `entries`.
  * `:pagination` - pagination params to pass to scrivener.

  """
  @spec from_address_to_transactions(Address.t(), [
          necessity_by_association_option | pagination_option
        ]) :: %Scrivener.Page{entries: [Transaction.t()]}
  def from_address_to_transactions(address = %Address{}, options \\ [])
      when is_list(options) do
    address_to_transactions(address, Keyword.put(options, :direction, :from))
  end

  @doc """
  TODO
  """
  def get_latest_block do
    Repo.one(from(b in Block, limit: 1, order_by: [desc: b.number]))
  end

  @doc """
  The `t:Explorer.Chain.Transaction.t/0` `gas_price` of the `transaction` in `unit`.
  """
  @spec gas_price(Transaction.t(), :wei) :: Wei.t()
  @spec gas_price(Transaction.t(), :gwei) :: Wei.gwei()
  @spec gas_price(Transaction.t(), :ether) :: Wei.ether()
  def gas_price(%Transaction{gas_price: gas_price}, unit) do
    Wei.to(gas_price, unit)
  end

  @doc """
  Converts `t:Explorer.Chain.Address.t/0` `hash` to the `t:Explorer.Chain.Address.t/0` with that `hash`.

  Returns `{:ok, %Explorer.Chain.Address{}}` if found

      iex> hash_to_address("0x0addressaddressaddressaddressaddressaddr")
      {:ok, %Explorer.Chain.Address{}}

  Returns `{:error, :not_found}` if not found

      iex> hash_to_address("0x1addressaddressaddressaddressaddressaddr")
      {:error, :not_found}

  """
  @spec hash_to_address(Address.hash()) :: {:ok, Address.t()} | {:error, :not_found}
  def hash_to_address(hash) do
    Address
    |> where_hash(hash)
    |> preload([:credit, :debit])
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      address -> {:ok, address}
    end
  end

  @doc """
  Converts `t:Explorer.Chain.Transaction.t/0` `hash` to the `t:Explorer.Chain.Transaction.t/0` with that `hash`.

  Returns `{:ok, %Explorer.Chain.Transaction{}}` if found

      iex> hash_to_transaction("0x0addressaddressaddressaddressaddressaddr")
      {:ok, %Explorer.Chain.Transaction{}}

  Returns `{:error, :not_found}` if not found

      iex> hash_to_transaction("0x1addressaddressaddressaddressaddressaddr")
      {:error, :not_found}

  ## Options

  * `:necessity_by_association` - use to load `t:association/0` as `:required` or `:optional`.  If an association is
      `:required`, and the `t:Explorer.Chain.Transaction.t/0` has no associated record for that association, then the
      `t:Explorer.Chain.Transaction.t/0` will not be included in the page `entries`.
  """
  @spec hash_to_transaction(Transaction.hash(), [necessity_by_association_option]) ::
          {:ok, Transaction.t()} | {:error, :not_found}
  def hash_to_transaction(hash, options \\ []) when is_list(options) do
    necessity_by_association = Keyword.get(options, :necessity_by_association, %{})

    Transaction
    |> join_associations(necessity_by_association)
    |> where_hash(hash)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      transaction -> {:ok, transaction}
    end
  end

  @doc """
  Converts `t:Explorer.Address.t/0` `id` to the `t:Explorer.Address.t/0` with that `id`.

  Returns `{:ok, %Explorer.Address{}}` if found

      iex> id_to_address(123)
      {:ok, %Address{}}

  Returns `{:error, :not_found}` if not found

      iex> id_to_address(456)
      {:error, :not_found}

  """
  @spec id_to_address(id :: non_neg_integer()) :: {:ok, Address.t()} | {:error, :not_found}
  def id_to_address(id) do
    Address
    |> Repo.get(id)
    |> case do
      nil ->
        {:error, :not_found}

      address ->
        {:ok, Repo.preload(address, [:credit, :debit])}
    end
  end

  @doc """
  TODO
  """
  def import_blocks(raw_blocks, internal_transactions, receipts) do
    {blocks, transactions} = extract_blocks(raw_blocks)

    Multi.new()
    |> Multi.run(:blocks, &insert_blocks(&1, blocks))
    |> Multi.run(:transactions, &insert_transactions(&1, transactions))
    |> Multi.run(:internal, &insert_internal(&1, internal_transactions))
    |> Multi.run(:receipts, &insert_receipts(&1, receipts))
    |> Multi.run(:logs, &insert_logs(&1))
    |> Repo.transaction()
  end

  def internal_transaction_count do
    Repo.one(from(t in InternalTransaction, select: count(t.id)))
  end

  @doc """
  The last `t:Explorer.Chain.Transaction.t/0` `id`.
  """
  @spec last_transaction_id([{:pending, boolean()}]) :: non_neg_integer()
  def last_transaction_id(options \\ []) when is_list(options) do
    query =
      from(
        t in Transaction,
        select: t.id,
        order_by: [desc: t.id],
        limit: 1
      )

    query
    |> where_pending(options)
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc """
  Finds all `t:Explorer.Chain.Transaction.t/0` in the `t:Explorer.Chain.Block.t/0`.

  ## Options

  * `:necessity_by_association` - use to load `t:association/0` as `:required` or `:optional`.  If an association is
      `:required`, and the `t:Explorer.Chain.Block.t/0` has no associated record for that association, then the
      `t:Explorer.Chain.Transaction.t/0` will not be included in the page `entries`.
  * `:pagination` - pagination params to pass to scrivener.

  """
  @spec list_blocks([necessity_by_association_option | pagination_option]) :: %Scrivener.Page{
          entries: [Block.t()]
        }
  def list_blocks(options \\ []) when is_list(options) do
    necessity_by_association = Keyword.get(options, :necessity_by_association, %{})
    pagination = Keyword.get(options, :pagination, %{})

    Block
    |> join_associations(necessity_by_association)
    |> order_by(desc: :number)
    |> Repo.paginate(pagination)
  end

  def log_count do
    Repo.one(from(l in Log, select: count(l.id)))
  end

  @doc """
  The maximum `t:Explorer.Chain.Block.t/0` `number`
  """
  @spec max_block_number() :: Block.block_number()
  def max_block_number do
    Repo.aggregate(Block, :max, :number)
  end

  @doc """
  TODO
  """
  def missing_block_numbers do
    {:ok, {_, missing_count, missing_ranges}} =
      Repo.transaction(fn ->
        query = from(b in Block, select: b.number, order_by: [asc: b.number])

        query
        |> Repo.stream(max_rows: 1000)
        |> Enum.reduce({-1, 0, []}, fn
          num, {prev, missing_count, acc} when prev + 1 == num ->
            {num, missing_count, acc}

          num, {prev, missing_count, acc} ->
            {num, missing_count + (num - prev - 1), [{prev + 1, num - 1} | acc]}
        end)
      end)

    {missing_count, missing_ranges}
  end

  @doc """
  Finds `t:Explorer.Chain.Block.t/0` with `number`
  """
  @spec number_to_block(Block.block_number()) :: {:ok, Block.t()} | {:error, :not_found}
  def number_to_block(number) do
    Block
    |> where(number: ^number)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      block -> {:ok, block}
    end
  end

  def receipt_count do
    Repo.one(from(r in Receipt, select: count(r.id)))
  end

  @doc """
  `t:Explorer.Chain.Transaction/0`s to `address`.

  ## Options

  * `:necessity_by_association` - use to load `t:association/0` as `:required` or `:optional`.  If an association is
      `:required`, and the `t:Explorer.Chain.Transaction.t/0` has no associated record for that association, then the
      `t:Explorer.Chain.Transaction.t/0` will not be included in the page `entries`.
  * `:pagination` - pagination params to pass to scrivener.

  """
  @spec to_address_to_transactions(Address.t(), [
          necessity_by_association_option | pagination_option
        ]) :: %Scrivener.Page{entries: [Transaction.t()]}
  def to_address_to_transactions(address = %Address{}, options \\ []) when is_list(options) do
    address_to_transactions(address, Keyword.put(options, :direction, :to))
  end

  @doc """
  Count of `t:Explorer.Chain.Transaction.t/0`.

  ## Options

  * `:pending`
    * `true` - only count pending transactions
    * `false` - count all transactions

  """
  @spec transaction_count([{:pending, boolean()}]) :: non_neg_integer()
  def transaction_count(options \\ []) when is_list(options) do
    Transaction
    |> where_pending(options)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  `t:Explorer.Chain.InternalTransaction/0`s in `t:Explorer.Chain.Transaction.t/0` with `hash`

  ## Options

  * `:necessity_by_association` - use to load `t:association/0` as `:required` or `:optional`.  If an association is
      `:required`, and the `t:Explorer.Chain.InternalTransaction.t/0` has no associated record for that association,
      then the `t:Explorer.Chain.InternalTransaction.t/0` will not be included in the list.

  """
  @spec transaction_hash_to_internal_transactions(Transaction.hash()) :: [InternalTransaction.t()]
  def transaction_hash_to_internal_transactions(hash, options \\ [])
      when is_binary(hash) and is_list(options) do
    necessity_by_association = Keyword.get(options, :necessity_by_association, %{})

    InternalTransaction
    |> for_parent_transaction(hash)
    |> join_associations(necessity_by_association)
    |> Repo.all()
  end

  @doc """
  Returns the list of transactions that occurred recently (10) before `t:Explorer.Chain.Transaction.t/0` `id`.

  ## Examples

      iex> Explorer.Chain.list_transactions_before_id(id)
      [%Explorer.Chain.Transaction{}, ...]

  ## Options

  * `:necessity_by_association` - use to load `t:association/0` as `:required` or `:optional`.  If an association is
      `:required`, and the `t:Explorer.Chain.InternalTransaction.t/0` has no associated record for that association,
      then the `t:Explorer.Chain.InternalTransaction.t/0` will not be included in the list.

  """
  @spec transactions_recently_before_id(id :: non_neg_integer, [necessity_by_association_option]) :: [
          Transaction.t()
        ]
  def transactions_recently_before_id(id, options \\ []) when is_list(options) do
    necessity_by_association = Keyword.get(options, :necessity_by_association, %{})

    Transaction
    |> join_associations(necessity_by_association)
    |> recently_before_id(id)
    |> where_pending(options)
    |> Repo.all()
  end

  @doc """
  Finds all `t:Explorer.Chain.Log.t/0`s for `t:Explorer.Chain.Transaction.t/0`.

  ## Options

  * `:necessity_by_association` - use to load `t:association/0` as `:required` or `:optional`.  If an association is
      `:required`, and the `t:Explorer.Chain.Log.t/0` has no associated record for that association, then the
      `t:Explorer.Chain.Log.t/0` will not be included in the page `entries`.
  * `:pagination` - pagination params to pass to scrivener.

  """
  @spec transaction_to_logs(Transaction.t(), [
          necessity_by_association_option | pagination_option
        ]) :: %Scrivener.Page{entries: [Log.t()]}
  def transaction_to_logs(%Transaction{hash: hash}, options \\ []) when is_list(options) do
    transaction_hash_to_logs(hash, options)
  end

  @doc """
  Converts `transaction` with its `receipt` loaded to the status of the `t:Explorer.Chain.Transaction.t/0`.

  ## Returns

  * `:failed` - the transaction failed without running out of gas
  * `:pending` - the transaction has not be confirmed in a block yet
  * `:out_of_gas` - the transaction failed because it ran out of gas
  * `:success` - the transaction has been confirmed in a block

  """
  @spec transaction_to_status(Transaction.t()) :: :failed | :pending | :out_of_gas | :success
  def transaction_to_status(%Transaction{receipt: nil}), do: :pending
  def transaction_to_status(%Transaction{receipt: %Receipt{status: 1}}), do: :success

  def transaction_to_status(%Transaction{
        gas: gas,
        receipt: %Receipt{gas_used: gas_used, status: 0}
      })
      when gas_used >= gas do
    :out_of_gas
  end

  def transaction_to_status(%Transaction{receipt: %Receipt{status: 0}}), do: :failed

  @doc """
  Updates `balance` of `t:Explorer.Address.t/0` with `hash`.

  If `t:Explorer.Address.t/0` with `hash` does not already exist, it is created first.
  """
  @spec update_balance(Address.hash(), Address.balance()) ::
          {:ok, Address.t()} | {:error, Ecto.Changeset.t()} | {:error, reason :: term}
  def update_balance(hash, balance) when is_binary(hash) do
    changes = %{
      balance: balance
    }

    with {:ok, address} <- ensure_hash_address(hash) do
      address
      |> Address.balance_changeset(changes)
      |> Repo.update()
    end
  end

  @doc """
  The `t:Explorer.Chain.Transaction.t/0` or `t:Explorer.Chain.InternalTransaction.t/0` `value` of the `transaction` in
  `unit`.
  """
  @spec value(InternalTransaction.t(), :wei) :: Wei.t()
  @spec value(InternalTransaction.t(), :gwei) :: Wei.gwei()
  @spec value(InternalTransaction.t(), :ether) :: Wei.ether()
  @spec value(Transaction.t(), :wei) :: Wei.t()
  @spec value(Transaction.t(), :gwei) :: Wei.gwei()
  @spec value(Transaction.t(), :ether) :: Wei.ether()
  def value(%type{value: value}, unit) when type in [InternalTransaction, Transaction] do
    Wei.to(value, unit)
  end

  ## Private Functions

  defp address_id_to_transactions(address_id, named_arguments)
       when is_integer(address_id) and is_list(named_arguments) do
    field =
      case Keyword.fetch!(named_arguments, :direction) do
        :to -> :to_address_id
        :from -> :from_address_id
      end

    necessity_by_association = Keyword.get(named_arguments, :necessity_by_association, %{})
    pagination = Keyword.get(named_arguments, :pagination, %{})

    Transaction
    |> join_associations(necessity_by_association)
    |> chronologically()
    |> where([t], field(t, ^field) == ^address_id)
    |> Repo.paginate(pagination)
  end

  defp address_to_transactions(%Address{id: address_id}, options) when is_list(options) do
    address_id_to_transactions(address_id, options)
  end

  defp chronologically(query) do
    from(q in query, order_by: [desc: q.inserted_at, desc: q.id])
  end

  defp extract_blocks(raw_blocks) do
    timestamps = timestamps()

    {blocks, transactions} =
      Enum.reduce(raw_blocks, {[], []}, fn raw_block, {blocks_acc, trans_acc} ->
        {:ok, block, transactions} = Block.extract(raw_block, timestamps)
        {[block | blocks_acc], trans_acc ++ transactions}
      end)

    {Enum.reverse(blocks), transactions}
  end

  defp for_parent_transaction(query, hash) when is_binary(hash) do
    from(
      child in query,
      inner_join: transaction in assoc(child, :transaction),
      where: fragment("lower(?)", transaction.hash) == ^String.downcase(hash)
    )
  end

  defp insert_blocks(%{}, blocks) do
    {_, inserted_blocks} =
      Repo.safe_insert_all(
        Block,
        blocks,
        returning: [:id, :number],
        on_conflict: :replace_all,
        conflict_target: :number
      )

    {:ok, inserted_blocks}
  end

  defp insert_internal(%{transactions: transactions}, internal_transactions) do
    timestamps = timestamps()

    internals =
      Enum.flat_map(transactions, fn %{hash: hash, id: id} ->
        case Map.fetch(internal_transactions, hash) do
          {:ok, traces} ->
            Enum.map(traces, &InternalTransaction.extract(&1, id, timestamps))

          :error ->
            []
        end
      end)

    {_, inserted} = Repo.safe_insert_all(InternalTransaction, internals, on_conflict: :nothing)

    {:ok, inserted}
  end

  defp insert_logs(%{receipts: %{inserted: receipts, logs: logs_map}}) do
    logs_to_insert =
      Enum.reduce(receipts, [], fn receipt, acc ->
        case Map.fetch(logs_map, receipt.transaction_id) do
          {:ok, []} ->
            acc

          {:ok, [_ | _] = logs} ->
            logs = Enum.map(logs, &Map.put(&1, :receipt_id, receipt.id))
            logs ++ acc
        end
      end)

    {_, inserted_logs} = Repo.safe_insert_all(Log, logs_to_insert, returning: [:id])
    {:ok, inserted_logs}
  end

  defp insert_receipts(%{transactions: transactions}, raw_receipts) do
    timestamps = timestamps()

    {receipts_to_insert, logs_map} =
      Enum.reduce(transactions, {[], %{}}, fn trans, {receipts_acc, logs_acc} ->
        case Map.fetch(raw_receipts, trans.hash) do
          {:ok, raw_receipt} ->
            {receipt, logs} = Receipt.extract(raw_receipt, trans.id, timestamps)
            {[receipt | receipts_acc], Map.put(logs_acc, trans.id, logs)}

          :error ->
            {receipts_acc, logs_acc}
        end
      end)

    {_, inserted_receipts} =
      Repo.safe_insert_all(
        Receipt,
        receipts_to_insert,
        returning: [:id, :transaction_id]
      )

    {:ok, %{inserted: inserted_receipts, logs: logs_map}}
  end

  defp insert_transactions(%{blocks: blocks}, transactions) do
    blocks_map = for block <- blocks, into: %{}, do: {block.number, block}

    transactions =
      for transaction <- transactions do
        %{id: id} = Map.fetch!(blocks_map, transaction.block_number)

        transaction
        |> Map.put(:block_id, id)
        |> Map.delete(:block_number)
      end

    {_, inserted} = Repo.safe_insert_all(Transaction, transactions, returning: [:id, :hash])

    {:ok, inserted}
  end

  defp join_association(query, association, necessity) when is_atom(association) do
    case necessity do
      :optional ->
        preload(query, ^association)

      :required ->
        from(q in query, inner_join: a in assoc(q, ^association), preload: [{^association, a}])
    end
  end

  defp join_associations(query, necessity_by_association) when is_map(necessity_by_association) do
    Enum.reduce(necessity_by_association, query, fn {association, join}, acc_query ->
      join_association(acc_query, association, join)
    end)
  end

  defp recently_before_id(query, id) do
    from(
      q in query,
      where: q.id < ^id,
      order_by: [desc: q.id],
      limit: 10
    )
  end

  defp timestamps do
    now = Ecto.DateTime.utc()
    %{inserted_at: now, updated_at: now}
  end

  defp transaction_hash_to_logs(transaction_hash, options)
       when is_binary(transaction_hash) and is_list(options) do
    lower_transaction_hash = String.downcase(transaction_hash)
    necessity_by_association = Keyword.get(options, :necessity_by_association, %{})
    pagination = Keyword.get(options, :pagination, %{})

    query =
      from(
        log in Log,
        join: transaction in assoc(log, :transaction),
        where: fragment("lower(?)", transaction.hash) == ^lower_transaction_hash,
        order_by: [asc: :index]
      )

    query
    |> join_associations(necessity_by_association)
    |> Repo.paginate(pagination)
  end

  defp where_hash(query, hash) do
    from(
      q in query,
      where: fragment("lower(?)", q.hash) == ^String.downcase(hash)
    )
  end

  defp where_pending(query, options) when is_list(options) do
    pending = Keyword.get(options, :pending, false)

    where_pending(query, pending)
  end

  defp where_pending(query, false), do: query

  defp where_pending(query, true) do
    from(
      transaction in query,
      where:
        fragment(
          "NOT EXISTS (SELECT true FROM receipts WHERE receipts.transaction_id = ?)",
          transaction.id
        )
    )
  end
end
