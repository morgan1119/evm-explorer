defmodule ExplorerWeb.Router do
  use ExplorerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug SetLocale, gettext: ExplorerWeb.Gettext, default_locale: "en"
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ExplorerWeb do
    pipe_through :browser
    get "/", PageController, :dummy
  end

  scope "/:locale", ExplorerWeb do
    pipe_through :browser # Use the default browser stack
    get "/", PageController, :index
  end
end
