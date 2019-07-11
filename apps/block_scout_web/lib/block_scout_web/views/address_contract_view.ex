defmodule BlockScoutWeb.AddressContractView do
  use BlockScoutWeb, :view

  alias Explorer.Chain.{Address, Data, InternalTransaction}

  def render("scripts.html", %{conn: conn}) do
    render_scripts(conn, "address_contract/code_highlighting.js")
  end

  def format_smart_contract_abi(abi), do: Poison.encode!(abi, pretty: false)

  @doc """
  Returns the correct format for the optimization text.

    iex> BlockScoutWeb.AddressContractView.format_optimization_text(true)
    "true"

    iex> BlockScoutWeb.AddressContractView.format_optimization_text(false)
    "false"
  """
  def format_optimization_text(true), do: gettext("true")
  def format_optimization_text(false), do: gettext("false")

  def format_external_libraries(libraries) do
    Enum.reduce(libraries, "", fn %{name: name, address_hash: address_hash}, acc ->
      acc <> name <> " : " <> address_hash <> "\n"
    end)
  end

  def contract_lines_with_index(contract_source_code) do
    contract_lines = String.split(contract_source_code, "\n")

    max_digits =
      contract_lines
      |> Enum.count()
      |> Integer.digits()
      |> Enum.count()

    contract_lines
    |> Enum.with_index(1)
    |> Enum.map(fn {value, line} ->
      {value, String.pad_leading(to_string(line), max_digits, " ")}
    end)
  end

  def contract_creation_code(%Address{
        contract_code: %Data{bytes: <<>>},
        contracts_creation_internal_transaction: %InternalTransaction{init: init}
      }) do
    {:selfdestructed, init}
  end

  def contract_creation_code(%Address{contract_code: contract_code}) do
    {:ok, contract_code}
  end
end
