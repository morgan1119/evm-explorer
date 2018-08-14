defmodule ExplorerWeb.API.RPC.RPCView do
  use ExplorerWeb, :view

  def render("show.json", %{data: data}) do
    %{
      "status" => "1",
      "message" => "OK",
      "result" => data
    }
  end

  def render("error.json", %{error: message} = assigns) do
    %{
      "status" => "0",
      "message" => message,
      "result" => Map.get(assigns, :data)
    }
  end
end
