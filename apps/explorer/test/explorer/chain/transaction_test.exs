defmodule Explorer.Chain.TransactionTest do
  use Explorer.DataCase

  alias Ecto.Changeset
  alias Explorer.Chain.Transaction

  doctest Transaction

  describe "changeset/2" do
    test "with valid attributes" do
      assert %Changeset{valid?: true} =
               Transaction.changeset(%Transaction{}, %{
                 from_address_hash: "0xe8ddc5c7a2d2f0d7a9798459c0104fdf5e987aca",
                 hash: "0x9fc76417374aa880d4449a1f7f31ec597f00b1f6f3dd2d66f4c9c6c445836d8b",
                 value: 1,
                 gas: 21000,
                 gas_price: 10000,
                 input: "0x5c8eff12",
                 nonce: "31337",
                 r: 0x9,
                 s: 0x10,
                 transaction_index: "0x12",
                 v: 27
               })
    end

    test "with invalid attributes" do
      changeset = Transaction.changeset(%Transaction{}, %{racecar: "yellow ham"})
      refute changeset.valid?
    end

    test "it creates a new to address" do
      params = params_for(:transaction, from_address_hash: "0xe8ddc5c7a2d2f0d7a9798459c0104fdf5e987aca")
      to_address_params = %{hash: "sk8orDi3"}
      changeset_params = Map.merge(params, %{to_address: to_address_params})

      assert %Changeset{valid?: true} = Transaction.changeset(%Transaction{}, changeset_params)
    end
  end
end
