defmodule Explorer.Counters.AverageBlockTime do
  use GenServer

  @moduledoc """
  Caches the number of token holders of a token.
  """

  import Ecto.Query, only: [from: 2]

  alias Explorer.Chain.Block
  alias Explorer.Repo
  alias Timex.Duration

  @doc """
  Starts a process to periodically update the counter of the token holders.
  """
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def average_block_time(block \\ nil) do
    enabled? =
      :explorer
      |> Application.fetch_env!(__MODULE__)
      |> Keyword.fetch!(:enabled)

    if enabled? do
      block = if block, do: {block.number, DateTime.to_unix(block.timestamp, :millisecond)}
      GenServer.call(__MODULE__, {:average_block_time, block})
    else
      {:error, :disabled}
    end
  end

  ## Server
  @impl true
  def init(_) do
    timestamps_query =
      from(block in Block,
        limit: 100,
        offset: 1,
        order_by: [desc: block.number],
        select: {block.number, block.timestamp}
      )

    timestamps =
      timestamps_query
      |> Repo.all()
      |> Enum.map(fn {number, timestamp} ->
        {number, DateTime.to_unix(timestamp, :millisecond)}
      end)

    {:ok, %{timestamps: timestamps, average: average_distance(timestamps)}}
  end

  @impl true
  def handle_call({:average_block_time, nil}, _from, %{average: average} = state), do: {:reply, average, state}

  def handle_call({:average_block_time, block}, _from, state) do
    state = add_block(state, block)
    {:reply, state.average, state}
  end

  # This is pretty naive, but we'll only ever be sorting 100 dates so I don't think
  # complex logic is really necessary here.
  defp add_block(%{timestamps: timestamps} = state, {new_number, _} = block) do
    if Enum.any?(timestamps, fn {number, _} -> number == new_number end) do
      state
    else
      timestamps =
        [block | timestamps]
        |> Enum.sort_by(fn {number, _} -> number end, &Kernel.>/2)
        |> Enum.take(100)

      %{state | timestamps: timestamps, average: average_distance(timestamps)}
    end
  end

  defp average_distance([]), do: Duration.from_milliseconds(0)
  defp average_distance([_]), do: Duration.from_milliseconds(0)

  defp average_distance(timestamps) do
    durations = durations(timestamps)

    {sum, count} =
      Enum.reduce(durations, {0, 0}, fn duration, {sum, count} ->
        {sum + duration, count + 1}
      end)

    average = sum / count

    average
    |> round()
    |> Duration.from_milliseconds()
  end

  defp durations(timestamps) do
    timestamps
    |> Enum.reduce({[], nil}, fn {_, timestamp}, {durations, last_timestamp} ->
      if last_timestamp do
        duration = last_timestamp - timestamp
        {[duration | durations], timestamp}
      else
        {durations, timestamp}
      end
    end)
    |> elem(0)
  end
end
