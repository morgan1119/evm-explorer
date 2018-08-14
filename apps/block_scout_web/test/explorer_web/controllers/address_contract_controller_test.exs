defmodule ExplorerWeb.AddressContractControllerTest do
  use ExplorerWeb.ConnCase

  import ExplorerWeb.Router.Helpers, only: [address_contract_path: 4]

  alias Explorer.Factory
  alias Explorer.Chain.Hash
  alias Explorer.ExchangeRates.Token

  describe "GET index/3" do
    test "returns not found for unexistent address", %{conn: conn} do
      unexistent_address_hash = Hash.to_string(Factory.address_hash())

      conn = get(conn, address_contract_path(ExplorerWeb.Endpoint, :index, :en, unexistent_address_hash))

      assert html_response(conn, 404)
    end

    test "returns not found given an invalid address hash ", %{conn: conn} do
      invalid_hash = "invalid_hash"

      conn = get(conn, address_contract_path(ExplorerWeb.Endpoint, :index, :en, invalid_hash))

      assert html_response(conn, 404)
    end

    test "returns not found when the address isn't a contract", %{conn: conn} do
      address = insert(:address)

      conn = get(conn, address_contract_path(ExplorerWeb.Endpoint, :index, :en, address))

      assert html_response(conn, 404)
    end

    test "successfully renders the page when the address is a contract", %{conn: conn} do
      address = insert(:address, contract_code: Factory.data("contract_code"), smart_contract: nil)

      transaction = insert(:transaction, from_address: address)

      insert(
        :internal_transaction_create,
        index: 0,
        transaction: transaction,
        created_contract_address: address
      )

      conn = get(conn, address_contract_path(ExplorerWeb.Endpoint, :index, :en, address))

      assert html_response(conn, 200)
      assert address.hash == conn.assigns.address.hash
      assert %Token{} = conn.assigns.exchange_rate
      assert conn.assigns.transaction_count
    end
  end
end
