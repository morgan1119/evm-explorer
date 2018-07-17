defmodule Indexer.Sequence do
  @moduledoc false

  use GenServer

  @enforce_keys ~w(current queue step)a
  defstruct current: nil,
            queue: nil,
            step: nil

  @typedoc """
  The ranges to stream from the `t:Stream.t/` returned from `build_stream/1`
  """
  @type ranges :: [Range.t()]

  @typep ranges_option :: {:ranges, ranges}

  @typedoc """
  The first number in the sequence to start for infinite sequences.
  """
  @type first :: integer()

  @typep first_option :: {:first, first}

  @typedoc """
   * `:finite` - only popping ranges from `queue`.
   * `:infinite` - generating new ranges from `current` and `step` when `queue` is empty.
  """
  @type mode :: :finite | :infinite

  @typedoc """
  The size of `t:Range.t/0` to construct based on the `t:first_named_argument/0` or its current value when all
  `t:prefix/0` ranges and any `t:Range.t/0`s injected with `inject_range/2` are consumed.
  """
  @type step :: neg_integer() | pos_integer()

  @typep step_named_argument :: {:step, step}

  @type options :: [ranges_option | first_option | step_named_argument]

  @typep t :: %__MODULE__{
           queue: :queue.queue(Range.t()),
           current: nil | integer(),
           step: step()
         }

  @doc """
  Starts a process for managing a block sequence.

  Infinite sequence

      Indexer.Sequence.start_link(first: 100, step: 10)

  Finite sequence

      Indexer.Sequence.start_link(ranges: [100..0])

  """
  @spec start_link(options) :: GenServer.on_start()
  def start_link(options) when is_list(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @doc """
  Builds an enumerable stream using a sequencer agent.
  """
  @spec build_stream(pid()) :: Enumerable.t()
  def build_stream(sequencer) when is_pid(sequencer) do
    Stream.resource(
      fn -> sequencer end,
      fn seq ->
        case pop(seq) do
          :halt -> {:halt, seq}
          range -> {[range], seq}
        end
      end,
      fn seq -> seq end
    )
  end

  @doc """
  Changes the mode for the sequence to finite.
  """
  @spec cap(pid()) :: mode
  def cap(sequence) when is_pid(sequence) do
    GenServer.call(sequence, :cap)
  end

  @doc """
  Adds a range of block numbers to the end of sequence.
  """
  @spec queue(pid(), Range.t()) :: :ok
  def queue(sequence, _first.._last = range) when is_pid(sequence) do
    GenServer.call(sequence, {:queue, range})
  end

  @doc """
  Pops the next block range from the sequence.
  """
  @spec pop(pid()) :: Range.t() | :halt
  def pop(sequence) when is_pid(sequence) do
    GenServer.call(sequence, :pop)
  end

  @impl GenServer
  @spec init(options) :: {:ok, t}
  def init(options) when is_list(options) do
    Process.flag(:trap_exit, true)

    case validate_options(options) do
      {:ok, %{ranges: ranges, first: first, step: step}} ->
        initial_queue = :queue.new()
        queue = queue_chunked_ranges(initial_queue, step, ranges)

        {:ok, %__MODULE__{queue: queue, current: first, step: step}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer

  @spec handle_call(:cap, GenServer.from(), %__MODULE__{current: nil}) :: {:reply, :finite, %__MODULE__{current: nil}}
  @spec handle_call(:cap, GenServer.from(), %__MODULE__{current: integer()}) ::
          {:reply, :infinite, %__MODULE__{current: nil}}
  def handle_call(:cap, _from, %__MODULE__{current: current} = state) do
    mode =
      case current do
        nil -> :finite
        _ -> :infinite
      end

    {:reply, mode, %__MODULE__{state | current: nil}}
  end

  @spec handle_call({:queue, Range.t()}, GenServer.from(), t()) :: {:reply, :ok, t()}
  def handle_call({:queue, _first.._last = range}, _from, %__MODULE__{queue: queue, step: step} = state) do
    {:reply, :ok, %__MODULE__{state | queue: queue_chunked_range(queue, step, range)}}
  end

  @spec handle_call(:pop, GenServer.from(), t()) :: {:reply, Range.t() | :halt, t()}
  def handle_call(:pop, _from, %__MODULE__{queue: queue, current: current, step: step} = state) do
    {reply, new_state} =
      case {current, :queue.out(queue)} do
        {_, {{:value, range}, new_queue}} ->
          {range, %__MODULE__{state | queue: new_queue}}

        {nil, {:empty, new_queue}} ->
          {:halt, %__MODULE__{state | queue: new_queue}}

        {_, {:empty, new_queue}} ->
          case current + step do
            new_current ->
              last = new_current - sign(step)
              {current..last, %__MODULE__{state | current: new_current, queue: new_queue}}
          end
      end

    {:reply, reply, new_state}
  end

  defp queue_chunked_range(queue, step, _.._ = range) when is_integer(step) do
    queue_chunked_ranges(queue, step, [range])
  end

  defp queue_chunked_ranges(queue, step, ranges) when is_integer(step) and is_list(ranges) do
    reduce_chunked_ranges(ranges, abs(step), queue, &:queue.in/2)
  end

  defp reduce_chunked_ranges(ranges, size, initial, reducer)
       when is_list(ranges) and is_integer(size) and size > 0 and is_function(reducer, 2) do
    Enum.reduce(ranges, initial, &reduce_chunked_range(&1, size, &2, reducer))
  end

  defp reduce_chunked_range(_.._ = range, size, initial, reducer) do
    count = Enum.count(range)
    reduce_chunked_range(range, count, size, initial, reducer)
  end

  defp reduce_chunked_range(_.._ = range, count, size, initial, reducer) when count <= size do
    reducer.(range, initial)
  end

  defp reduce_chunked_range(first..last = range, _, size, initial, reducer) do
    {sign, comparator} =
      if first < last do
        {1, &Kernel.>=/2}
      else
        {-1, &Kernel.<=/2}
      end

    step = sign * size

    first
    |> Stream.iterate(&(&1 + step))
    |> Enum.reduce_while(initial, fn chunk_first, acc ->
      next_chunk_first = chunk_first + step
      full_chunk_last = next_chunk_first - sign

      {action, chunk_last} =
        if comparator.(full_chunk_last, last) do
          {:halt, last}
        else
          {:cont, full_chunk_last}
        end

      {action, reducer.(chunk_first..chunk_last, acc)}
    end)
  end

  @spec sign(neg_integer()) :: -1
  defp sign(integer) when integer < 0, do: -1

  @spec sign(non_neg_integer()) :: 1
  defp sign(_), do: 1

  defp validate_options(options) do
    step = Keyword.fetch!(options, :step)

    case {Keyword.fetch(options, :ranges), Keyword.fetch(options, :first)} do
      {:error, {:ok, first}} ->
        {:ok, %{ranges: [], first: first, step: step}}

      {{:ok, ranges}, :error} ->
        {:ok, %{ranges: ranges, first: nil, step: step}}

      {{:ok, _}, {:ok, _}} ->
        {:error,
         ":ranges and :first cannot be set at the same time as :ranges is for :finite mode while :first is for :infinite mode"}

      {:error, :error} ->
        {:error, "either :ranges or :first must be set"}
    end
  end
end
