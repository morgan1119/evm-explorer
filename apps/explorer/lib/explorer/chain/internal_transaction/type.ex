defmodule Explorer.Chain.InternalTransaction.Type do
  @moduledoc """
  Internal transaction types
  """

  @behaviour Ecto.Type

  @typedoc """
   * `:call`
   * `:create`
   * `:reward`
   * `:suicide`
  """
  @type t :: :call | :create | :reward | :suicide

  @doc """
  Casts `term` to `t:t/0`

  If the `term` is already in `t:t/0`, then it is returned

      iex> Explorer.Chain.InternalTransaction.Type.cast(:call)
      {:ok, :call}
      iex> Explorer.Chain.InternalTransaction.Type.cast(:create)
      {:ok, :create}
      iex> Explorer.Chain.InternalTransaction.Type.cast(:reward)
      {:ok, :reward}
      iex> Explorer.Chain.InternalTransaction.Type.cast(:suicide)
      {:ok, :suicide}

  If `term` is a `String.t`, then it is converted to the corresponding `t:t/0`.

      iex> Explorer.Chain.InternalTransaction.Type.cast("call")
      {:ok, :call}
      iex> Explorer.Chain.InternalTransaction.Type.cast("create")
      {:ok, :create}
      iex> Explorer.Chain.InternalTransaction.Type.cast("reward")
      {:ok, :reward}
      iex> Explorer.Chain.InternalTransaction.Type.cast("suicide")
      {:ok, :suicide}

  Unsupported `String.t` return an `:error`.

      iex> Explorer.Chain.InternalTransaction.Type.cast("hard-fork")
      :error

  """
  @impl Ecto.Type
  @spec cast(term()) :: {:ok, t()} | :error
  def cast(t) when t in ~w(call create suicide reward)a, do: {:ok, t}
  def cast("call"), do: {:ok, :call}
  def cast("create"), do: {:ok, :create}
  def cast("reward"), do: {:ok, :reward}
  def cast("suicide"), do: {:ok, :suicide}
  def cast(_), do: :error

  @doc """
  Dumps the `atom` format to `String.t` format used in the database.

      iex> Explorer.Chain.InternalTransaction.Type.dump(:call)
      {:ok, "call"}
      iex> Explorer.Chain.InternalTransaction.Type.dump(:create)
      {:ok, "create"}
      iex> Explorer.Chain.InternalTransaction.Type.dump(:reward)
      {:ok, "reward"}
      iex> Explorer.Chain.InternalTransaction.Type.dump(:suicide)
      {:ok, "suicide"}

  Other atoms return an error

      iex> Explorer.Chain.InternalTransaction.Type.dump(:other)
      :error

  """
  @impl Ecto.Type
  @spec dump(term()) :: {:ok, String.t()} | :error
  def dump(:call), do: {:ok, "call"}
  def dump(:create), do: {:ok, "create"}
  def dump(:reward), do: {:ok, "reward"}
  def dump(:suicide), do: {:ok, "suicide"}
  def dump(_), do: :error

  @doc """
  Loads the `t:String.t/0` from the database.

      iex> Explorer.Chain.InternalTransaction.Type.load("call")
      {:ok, :call}
      iex> Explorer.Chain.InternalTransaction.Type.load("create")
      {:ok, :create}
      iex> Explorer.Chain.InternalTransaction.Type.load("reward")
      {:ok, :reward}
      iex> Explorer.Chain.InternalTransaction.Type.load("suicide")
      {:ok, :suicide}

  Other `t:String.t/0` return `:error`

      iex> Explorer.Chain.InternalTransaction.Type.load("other")
      :error

  """
  @impl Ecto.Type
  @spec load(term()) :: {:ok, t()} | :error
  def load("call"), do: {:ok, :call}
  def load("create"), do: {:ok, :create}
  def load("reward"), do: {:ok, :reward}
  def load("suicide"), do: {:ok, :suicide}
  def load(_), do: :error

  @doc """
  The underlying database type: `:string`
  """
  @impl Ecto.Type
  @spec type() :: :string
  def type, do: :string
end
