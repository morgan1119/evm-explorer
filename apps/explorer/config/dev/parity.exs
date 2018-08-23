use Mix.Config

config :explorer,
  json_rpc_named_arguments: [
    transport: EthereumJSONRPC.HTTP,
    transport_options: [
      http: EthereumJSONRPC.HTTP.HTTPoison,
      url: "https://sokol.poa.network",
      method_to_url: [
        eth_getBalance: "https://sokol-trace.poa.network",
        trace_replayTransaction: "https://sokol-trace.poa.network"
      ],
      http_options: [recv_timeout: 60_000, timeout: 60_000, hackney: [pool: :ethereum_jsonrpc]]
    ],
    variant: EthereumJSONRPC.Parity
  ],
  subscribe_named_arguments: [
    transport: EthereumJSONRPC.WebSocket,
    transport_options: [
      web_socket: EthereumJSONRPC.WebSocket.WebSockex,
      url: "wss://sokol-ws.poa.network/ws"
    ],
    variant: EthereumJSONRPC.Parity
  ]
