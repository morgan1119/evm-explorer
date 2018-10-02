use Mix.Config

config :indexer,
  block_interval: 5_000,
  json_rpc_named_arguments: [
    transport: EthereumJSONRPC.HTTP,
    transport_options: [
      http: EthereumJSONRPC.HTTP.HTTPoison,
      url: System.get_env("ETHEREUM_URL") || "https://sokol.poa.network",
      method_to_url: [
        eth_getBalance: System.get_env("TRACE_URL") || "https://sokol-trace.poa.network",
        trace_replayTransaction: System.get_env("TRACE_URL") || "https://sokol-trace.poa.network"
      ],
      http_options: [recv_timeout: 60_000, timeout: 60_000, hackney: [pool: :ethereum_jsonrpc]]
    ],
    variant: EthereumJSONRPC.Parity
  ],
  subscribe_named_arguments: [
    transport: EthereumJSONRPC.WebSocket,
    transport_options: [
      web_socket: EthereumJSONRPC.WebSocket.WebSocketClient,
      url: System.get_env("WS_URL") || "wss://sokol-ws.poa.network/ws"
    ]
  ]
