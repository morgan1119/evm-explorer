defmodule Explorer.AddressForm do
  @moduledoc false
  alias Explorer.Address
  alias Explorer.FromAddress
  alias Explorer.Repo
  alias Explorer.ToAddress
  alias Explorer.Transaction
  import Ecto.Query

  def build(address) do
    address
    |> Map.merge(%{
      balance: address |> calculate_balance,
    })
  end

  def calculate_balance(address) do
    Decimal.sub(credits(address), debits(address))
  end

  def credits(address) do
    query = from transaction in Transaction,
      join: to_address in ToAddress,
        where: to_address.transaction_id == transaction.id,
      join: address in Address,
        where: to_address.address_id == address.id,
      select: sum(transaction.value),
      where: address.id == ^address.id
    Repo.one(query) || Decimal.new(0)
  end

  def debits(address) do
    query = from transaction in Transaction,
      join: from_address in FromAddress,
        where: from_address.transaction_id == transaction.id,
      join: address in Address,
        where: from_address.address_id == address.id,
      select: sum(transaction.value),
      where: address.id == ^address.id
    Repo.one(query) || Decimal.new(0)
  end
end
