defmodule BlockScoutWeb.Router do
  use BlockScoutWeb, :router

  alias BlockScoutWeb.Plug.GraphQL
  alias BlockScoutWeb.{ApiRouter, WebRouter}

  forward("/wobserver", Wobserver.Web.Router)
  forward("/admin", BlockScoutWeb.AdminRouter)

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(BlockScoutWeb.CSPHeader)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api/v1", BlockScoutWeb.API.V1, as: :api_v1 do
    pipe_through(:api)
    get("/health", HealthController, :health)

    if Application.get_env(:block_scout_web, ApiRouter)[:writing_enabled] do
      post("/decompiled_smart_contract", DecompiledSmartContractController, :create)
      post("/verified_smart_contracts", VerifiedSmartContractController, :create)
    end
  end

  if Application.get_env(:block_scout_web, ApiRouter)[:reading_enabled] do
    forward("/api", ApiRouter)

    # Needs to be 200 to support the schema introspection for graphiql
    @max_complexity 200

    forward("/graphql", Absinthe.Plug,
      schema: BlockScoutWeb.Schema,
      analyze_complexity: true,
      max_complexity: @max_complexity
    )

    forward("/graphiql", Absinthe.Plug.GraphiQL,
      schema: BlockScoutWeb.Schema,
      interface: :advanced,
      default_query: GraphQL.default_query(),
      socket: BlockScoutWeb.UserSocket,
      analyze_complexity: true,
      max_complexity: @max_complexity
    )
  else
    scope "/", BlockScoutWeb do
      pipe_through(:browser)
      get("/api_docs", PageNotFoundController, :index)
      get("/eth_rpc_api_docs", PageNotFoundController, :index)
    end
  end

  scope "/", BlockScoutWeb do
    pipe_through(:browser)

    get("/api_docs", APIDocsController, :index)
    get("/eth_rpc_api_docs", APIDocsController, :eth_rpc)
  end

  scope "/verify_smart_contract" do
    pipe_through(:api)

    post("/contract_verifications", BlockScoutWeb.AddressContractVerificationController, :create)
  end

  if Application.get_env(:block_scout_web, WebRouter)[:enabled] do
    forward("/", BlockScoutWeb.WebRouter)
  else
    scope "/", BlockScoutWeb do
      pipe_through(:browser)

      forward("/", APIDocsController, :index)
    end
  end
end
