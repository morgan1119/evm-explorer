defmodule BlockScoutWeb.CurrencyHelpers do
  @moduledoc """
  Helper functions for interacting with `t:BlockScoutWeb.ExchangeRates.USD.t/0` values.
  """

  alias BlockScoutWeb.ExchangeRates.USD
  alias BlockScoutWeb.Cldr.Number

  @doc """
  Formats a `BlockScoutWeb.ExchangeRates.USD` value into USD and applies a unit label.

  ## Examples

      iex> format_usd_value(%USD{value: Decimal.new(0.0000001)})
      "< $0.000001 USD"

      iex> format_usd_value(%USD{value: Decimal.new(0.123456789)})
      "$0.123457 USD"

      iex> format_usd_value(%USD{value: Decimal.new(0.1234)})
      "$0.123400 USD"

      iex> format_usd_value(%USD{value: Decimal.new(1.23456789)})
      "$1.23 USD"

      iex> format_usd_value(%USD{value: Decimal.new(1.2)})
      "$1.20 USD"

      iex> format_usd_value(%USD{value: Decimal.new(123456.789)})
      "$123,457 USD"
  """
  @spec format_usd_value(USD.t() | nil) :: binary() | nil
  def format_usd_value(nil), do: nil

  def format_usd_value(%USD{value: nil}), do: nil

  def format_usd_value(%USD{value: value}) do
    cond do
      Decimal.cmp(value, "0.000001") == :lt -> "< $0.000001 USD"
      Decimal.cmp(value, 1) == :lt -> "$#{Number.to_string!(value, format: "0.000000")} USD"
      Decimal.cmp(value, 100_000) == :lt -> "$#{Number.to_string!(value, format: "#,###.00")} USD"
      true -> "$#{Number.to_string!(value, format: "#,###")} USD"
    end
  end

  @doc """
  Formats the given integer value to a currency format.

  ## Examples

      iex> BlockScoutWeb.CurrencyHelpers.format_integer_to_currency(1000000)
      "1,000,000"
  """
  @spec format_integer_to_currency(non_neg_integer()) :: String.t()
  def format_integer_to_currency(value) do
    {:ok, formatted} = Number.to_string(value, format: "#,##0")

    formatted
  end

  @doc """
  Formats the given amount according to given decimals.

  ## Examples

      iex> format_according_to_decimals(Decimal.new(20500000), 5)
      "205"

      iex> format_according_to_decimals(Decimal.new(20500000), 7)
      "2.05"

      iex> format_according_to_decimals(Decimal.new(205000), 12)
      "0.000000205"

      iex> format_according_to_decimals(Decimal.new(205000), 2)
      "2,050"

      iex> format_according_to_decimals(205000, 2)
      "2,050"
  """
  @spec format_according_to_decimals(non_neg_integer(), non_neg_integer()) :: String.t()
  def format_according_to_decimals(value, nil) do
    format_according_to_decimals(value, 0)
  end

  def format_according_to_decimals(value, decimals) when is_integer(value) do
    value
    |> Decimal.new()
    |> format_according_to_decimals(decimals)
  end

  @spec format_according_to_decimals(Decimal.t(), non_neg_integer()) :: String.t()
  def format_according_to_decimals(%Decimal{sign: sign, coef: coef, exp: exp}, decimals) do
    sign
    |> Decimal.new(coef, exp - decimals)
    |> Decimal.reduce()
    |> thousands_separator()
  end

  defp thousands_separator(value) do
    if Decimal.to_float(value) > 999 do
      Number.to_string!(value)
    else
      Decimal.to_string(value, :normal)
    end
  end
end
