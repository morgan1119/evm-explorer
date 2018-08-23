use Mix.Config

config :explorer,
  json_rpc_named_arguments: [
    transport: EthereumJSONRPC.HTTP,
    transport_options: [
      http: EthereumJSONRPC.HTTP.HTTPoison,
      url: System.get_env("ETHEREUM_JSONRPC_HTTP_URL") || "https://mainnet.infura.io/8lTvJTKmHPCHazkneJsY",
      http_options: [recv_timeout: 60_000, timeout: 60_000, hackney: [pool: :ethereum_jsonrpc]]
    ],
    variant: EthereumJSONRPC.Geth
  ],
  subscribe_named_arguments: [
    transport: EthereumJSONRPC.WebSocket,
    transport_options: [
      web_socket: EthereumJSONRPC.WebSocket.WebSockex,
      url: System.get_env("ETHEREUM_JSONRPC_WEB_SOCKET_URL") || "wss://mainnet.infura.io/8lTvJTKmHPCHazkneJsY/ws"
    ],
    variant: EthereumJSONRPC.Geth
  ]
