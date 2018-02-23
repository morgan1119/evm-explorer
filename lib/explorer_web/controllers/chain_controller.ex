defmodule ExplorerWeb.ChainController do
  use ExplorerWeb, :controller

  alias Explorer.Servers.ChainStatistics
  alias Explorer.Resource

  def show(conn, _params) do
    render(conn, "show.html", chain: ChainStatistics.fetch())
  end

  def search(conn, %{"q" => query}) do
    case Resource.lookup(query) do
      nil ->
        conn
        |> render(ExplorerWeb.ErrorView, "404.html")
      item ->
        redirect_search_results(conn, item)
    end
  end

  defp redirect_search_results(conn, %Explorer.Block{} = item) do
    redirect conn, to: block_path(conn, :show, Gettext.get_locale, item.number)
  end

  defp redirect_search_results(conn, %Explorer.Transaction{} = item) do
    redirect conn, to: transaction_path(
      conn, :show, Gettext.get_locale, item.hash
    )
  end

  defp redirect_search_results(conn, %Explorer.Address{} = item) do
    redirect conn, to: address_path(conn, :show, Gettext.get_locale, item.hash)
  end
end
