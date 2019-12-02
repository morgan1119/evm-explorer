defmodule Explorer.Chain.Cache.AddressSum do
  @moduledoc """
  Cache for address sum.
  """

  require Logger

  use Explorer.Chain.MapCache,
    name: :address_sum,
    key: :sum,
    key: :async_task,
    ttl_check_interval: Application.get_env(:explorer, __MODULE__)[:ttl_check_interval],
    global_ttl: Application.get_env(:explorer, __MODULE__)[:global_ttl],
    callback: &async_task_on_deletion(&1)

  alias Explorer.Chain

  defp handle_fallback(:sum) do
    result = fetch_from_db()

    if Application.get_env(:explorer, __MODULE__)[:enabled] do
      {:update, result}
    else
      {:return, result}
    end
  end

  defp handle_fallback(:async_task) do
    # If this gets called it means an async task was requested, but none exists
    # so a new one needs to be launched
    {:ok, task} =
      Task.start(fn ->
        try do
          result = fetch_from_db()

          set_sum(result)
        rescue
          e ->
            Logger.debug([
              "Coudn't update address sum test #{inspect(e)}"
            ])
        end

        set_async_task(nil)
      end)

    {:update, task}
  end

  defp fetch_from_db do
    Chain.fetch_sum_coin_total_supply()
  end

  # By setting this as a `callback` an async task will be started each time the
  # `sum` expires (unless there is one already running)
  defp async_task_on_deletion({:delete, _, :sum}), do: get_async_task()

  defp async_task_on_deletion(_data), do: nil
end
