defmodule BlockScoutWeb.CurrencyHelpersTest do
  use ExUnit.Case

  alias BlockScoutWeb.CurrencyHelpers
  alias BlockScoutWeb.ExchangeRates.USD

  doctest BlockScoutWeb.CurrencyHelpers, import: true

  test "with nil it returns nil" do
    assert nil == CurrencyHelpers.format_usd_value(nil)
  end

  test "with USD.null() it returns nil" do
    assert nil == CurrencyHelpers.format_usd_value(USD.null())
  end

  describe "format_according_to_decimals/1" do
    test "formats the amount as value considering the given decimals" do
      amount = Decimal.new(205_000_000_000_000)
      decimals = 12

      assert CurrencyHelpers.format_according_to_decimals(amount, decimals) == "205"
    end

    test "considers the decimal places according to the given decimals" do
      amount = Decimal.new(205_000)
      decimals = 12

      assert CurrencyHelpers.format_according_to_decimals(amount, decimals) == "0.000000205"
    end

    test "does not consider right zeros in decimal places" do
      amount = Decimal.new(90_000_000)
      decimals = 6

      assert CurrencyHelpers.format_according_to_decimals(amount, decimals) == "90"
    end

    test "returns the full number when there is no right zeros in decimal places" do
      amount = Decimal.new(9_324_876)
      decimals = 6

      assert CurrencyHelpers.format_according_to_decimals(amount, decimals) == "9.324876"
    end

    test "formats the value considering thousands separators" do
      amount = Decimal.new(1_000_450)
      decimals = 2

      assert CurrencyHelpers.format_according_to_decimals(amount, decimals) == "10,004.5"
    end

    test "supports value as integer" do
      amount = 1_000_450
      decimals = 2

      assert CurrencyHelpers.format_according_to_decimals(amount, decimals) == "10,004.5"
    end
  end

  describe "format_integer_to_currency/1" do
    test "formats the integer value to a currency format" do
      assert CurrencyHelpers.format_integer_to_currency(9000) == "9,000"
    end
  end
end
