use Mix.Config

config :explorer,
  json_rpc_named_arguments: [
    transport: EthereumJSONRPC.HTTP,
    transport_options: [
      http: EthereumJSONRPC.HTTP.HTTPoison,
      url: System.get_env("ETHEREUM_JSONRPC_HTTP_URL") || "http://54.234.12.105:8545",
      method_to_url: [
        eth_call: System.get_env("ETHEREUM_JSONRPC_TRACE_URL") || "http://54.234.12.105:8545",
        eth_getBalance: System.get_env("ETHEREUM_JSONRPC_TRACE_URL") || "http://54.234.12.105:8545",
        trace_replayTransaction: System.get_env("ETHEREUM_JSONRPC_TRACE_URL") || "http://54.234.12.105:8545"
      ],
      http_options: [recv_timeout: 60_000, timeout: 60_000, hackney: [pool: :ethereum_jsonrpc]]
    ],
    variant: EthereumJSONRPC.Parity
  ],
  subscribe_named_arguments: [
    transport: EthereumJSONRPC.WebSocket,
    transport_options: [
      web_socket: EthereumJSONRPC.WebSocket.WebSocketClient,
      url: System.get_env("ETHEREUM_JSONRPC_WS_URL") || "ws://54.234.12.105:8546"
    ],
    variant: EthereumJSONRPC.Parity
  ]
