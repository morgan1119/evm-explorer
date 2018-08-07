defmodule ExplorerWeb.TokenHelpers do
  @moduledoc """
  Helper functions for intereacting with `t:ExplorerWeb.Chain.Token` attributes.
  """

  alias Explorer.Chain.{Token, TokenTransfer}
  alias ExplorerWeb.{CurrencyHelpers}

  @doc """
  Returns the token transfers' amount according to the token's type and decimails.

  When the token's type is ERC-20, then we are going to format the amount according to the token's
  decimals considering 0 when the decimals is nil. Case the amount is nil, this function will
  return the symbol `--`.

  When the token's type is ERC-721, the function will return a string with the token_id that
  represents the ERC-721 token since this kind of token doesn't have amount and decimals.
  """
  def token_transfer_amount(%TokenTransfer{token: token, amount: amount, token_id: token_id}) do
    do_token_transfer_amount(token, amount, token_id)
  end

  defp do_token_transfer_amount(%Token{type: "ERC-20"}, nil, _token_id) do
    "--"
  end

  defp do_token_transfer_amount(%Token{type: "ERC-20", decimals: nil}, amount, _token_id) do
    CurrencyHelpers.format_according_to_decimals(amount, 0)
  end

  defp do_token_transfer_amount(%Token{type: "ERC-20", decimals: decimals}, amount, _token_id) do
    CurrencyHelpers.format_according_to_decimals(amount, decimals)
  end

  defp do_token_transfer_amount(%Token{type: "ERC-721"}, _amount, token_id) do
    "TokenID [#{token_id}]"
  end

  defp do_token_transfer_amount(_token, _amount, _token_id) do
    nil
  end

  @doc """
  Returns the token's symbol.

  When the token's symbol is nil, the function will return the contract address hash.
  """
  def token_symbol(%Token{symbol: nil, contract_address_hash: address_hash}) do
    address_hash =
      address_hash
      |> to_string()
      |> String.slice(0..6)

    "#{address_hash}..."
  end

  def token_symbol(%Token{symbol: symbol}) do
    symbol
  end
end
