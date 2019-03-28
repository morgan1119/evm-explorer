defmodule BlockScoutWeb.API.RPC.ContractController do
  use BlockScoutWeb, :controller

  alias BlockScoutWeb.API.RPC.Helpers
  alias Explorer.Chain
  alias Explorer.Chain.SmartContract

  def listcontracts(conn, params) do
    with pagination_options <- Helpers.put_pagination_options(%{}, params),
         {:params, {:ok, options}} <- {:params, add_filter(pagination_options, params)} do
      options_with_defaults =
        options
        |> Map.put_new(:page_number, 0)
        |> Map.put_new(:page_size, 10)

      contracts = list_contracts(options_with_defaults)

      conn
      |> put_status(200)
      |> render(:listcontracts, %{contracts: contracts})
    else
      {:params, {:error, error}} ->
        conn
        |> put_status(400)
        |> render(:error, error: error)
    end
  end

  def getabi(conn, params) do
    with {:address_param, {:ok, address_param}} <- fetch_address(params),
         {:format, {:ok, address_hash}} <- to_address_hash(address_param),
         {:contract, {:ok, contract}} <- to_smart_contract(address_hash) do
      render(conn, :getabi, %{abi: contract.abi})
    else
      {:address_param, :error} ->
        render(conn, :error, error: "Query parameter address is required")

      {:format, :error} ->
        render(conn, :error, error: "Invalid address hash")

      {:contract, :not_found} ->
        render(conn, :error, error: "Contract source code not verified")
    end
  end

  def getsourcecode(conn, params) do
    with {:address_param, {:ok, address_param}} <- fetch_address(params),
         {:format, {:ok, address_hash}} <- to_address_hash(address_param),
         {:contract, {:ok, contract}} <- to_smart_contract(address_hash) do
      render(conn, :getsourcecode, %{
        contract: contract,
        address_hash: address_hash
      })
    else
      {:address_param, :error} ->
        render(conn, :error, error: "Query parameter address is required")

      {:format, :error} ->
        render(conn, :error, error: "Invalid address hash")

      {:contract, :not_found} ->
        render(conn, :getsourcecode, %{contract: nil, address_hash: nil})
    end
  end

  defp list_contracts(%{page_number: page_number, page_size: page_size} = opts) do
    offset = (max(page_number, 1) - 1) * page_size

    case Map.get(opts, :filter) do
      :verified ->
        Chain.list_verified_contracts(page_size, offset)

      :decompiled ->
        Chain.list_decompiled_contracts(page_size, offset)

      :unverified ->
        Chain.list_unverified_contracts(page_size, offset)

      :not_decompiled ->
        Chain.list_not_decompiled_contracts(page_size, offset)

      _ ->
        Chain.list_contracts(page_size, offset)
    end
  end

  defp add_filter(options, params) do
    with {:param, {:ok, value}} <- {:param, Map.fetch(params, "filter")},
         {:validation, {:ok, filter}} <- {:validation, contracts_filter(value)} do
      {:ok, Map.put(options, :filter, filter)}
    else
      {:param, :error} -> {:ok, options}
      {:validation, {:error, error}} -> {:error, error}
    end
  end

  defp contracts_filter(nil), do: {:ok, nil}
  defp contracts_filter(1), do: {:ok, :verified}
  defp contracts_filter(2), do: {:ok, :decompiled}
  defp contracts_filter(3), do: {:ok, :unverified}
  defp contracts_filter(4), do: {:ok, :not_decompiled}
  defp contracts_filter("verified"), do: {:ok, :verified}
  defp contracts_filter("decompiled"), do: {:ok, :decompiled}
  defp contracts_filter("unverified"), do: {:ok, :unverified}
  defp contracts_filter("not_decompiled"), do: {:ok, :not_decompiled}

  defp contracts_filter(filter) when is_bitstring(filter) do
    case Integer.parse(filter) do
      {number, ""} -> contracts_filter(number)
      _ -> {:error, contracts_filter_error_message(filter)}
    end
  end

  defp contracts_filter(filter), do: {:error, contracts_filter_error_message(filter)}

  defp contracts_filter_error_message(filter) do
    "#{filter} is not a valid value for `filter`. Please use one of: verified, decompiled, unverified, not_decompiled, 1, 2, 3, 4."
  end

  defp fetch_address(params) do
    {:address_param, Map.fetch(params, "address")}
  end

  defp to_address_hash(address_hash_string) do
    {:format, Chain.string_to_address_hash(address_hash_string)}
  end

  defp to_smart_contract(address_hash) do
    result =
      case Chain.address_hash_to_smart_contract(address_hash) do
        nil ->
          :not_found

        contract ->
          {:ok, SmartContract.preload_decompiled_smart_contract(contract)}
      end

    {:contract, result}
  end
end
