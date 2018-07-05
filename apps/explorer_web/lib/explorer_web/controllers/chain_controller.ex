defmodule ExplorerWeb.ChainController do
  use ExplorerWeb, :controller

  alias Explorer.Chain.{Address, Block, Statistics, Transaction}
  alias Explorer.ExchangeRates.Token
  alias Explorer.Market
  alias ExplorerWeb.Chain

  def show(conn, _params) do
    transaction_estimated_count = Explorer.Chain.transaction_estimated_count()
    address_estimated_count = Explorer.Chain.address_estimated_count()

    render(
      conn,
      "show.html",
      address_estimated_count: address_estimated_count,
      chain: Statistics.fetch(),
      exchange_rate: Market.get_exchange_rate(Explorer.coin()) || Token.null(),
      market_history_data: Market.fetch_recent_history(30),
      transaction_estimated_count: transaction_estimated_count
    )
  end

  def search(conn, %{"q" => query}) do
    query
    |> String.trim()
    |> Chain.from_param()
    |> case do
      {:ok, item} ->
        redirect_search_results(conn, item)

      {:error, :not_found} ->
        not_found(conn)
    end
  end

  defp redirect_search_results(conn, %Address{} = item) do
    redirect(conn, to: address_path(conn, :show, Gettext.get_locale(), item))
  end

  defp redirect_search_results(conn, %Block{} = item) do
    redirect(conn, to: block_path(conn, :show, Gettext.get_locale(), item))
  end

  defp redirect_search_results(conn, %Transaction{} = item) do
    redirect(
      conn,
      to:
        transaction_path(
          conn,
          :show,
          Gettext.get_locale(),
          item
        )
    )
  end
end
