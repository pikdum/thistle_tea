defmodule ThistleTea.Game.Network.SessionsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Sessions

  setup [:registry]

  describe "authenticate/2 and count/1" do
    test "counts authenticated accounts and replaces a connection's identity" do
      assert Sessions.count(__MODULE__) == 0
      assert :ok = Sessions.authenticate(1, __MODULE__)
      assert :ok = Sessions.authenticate(1, __MODULE__)
      assert Sessions.count(__MODULE__) == 1
      assert :ok = Sessions.authenticate(2, __MODULE__)
      assert Sessions.count(__MODULE__) == 1
      assert [{2}] = Registry.select(__MODULE__, [{{:_, :_, :"$1"}, [], [{{:"$1"}}]}])
    end

    test "counts duplicate account connections once and removes disconnected owners" do
      parent = self()

      tasks =
        for account <- [1, 1, 2] do
          Task.async(fn ->
            Sessions.authenticate(account, __MODULE__)
            send(parent, {:authenticated, self()})

            receive do
              :disconnect -> :ok
            end
          end)
        end

      for task <- tasks, do: assert_receive({:authenticated, pid} when pid == task.pid)
      assert Sessions.count(__MODULE__) == 2
      [first, duplicate, other] = tasks
      send(first.pid, :disconnect)
      Task.await(first)
      assert Sessions.count(__MODULE__) == 2
      send(duplicate.pid, :disconnect)
      Task.await(duplicate)
      await_count(1)
      send(other.pid, :disconnect)
      Task.await(other)
      await_count(0)
    end
  end

  defp registry(_context) do
    start_supervised!({Sessions, name: __MODULE__})
    :ok
  end

  defp await_count(expected, attempts \\ 100)
  defp await_count(expected, 0), do: assert(Sessions.count(__MODULE__) == expected)

  defp await_count(expected, attempts) do
    if Sessions.count(__MODULE__) == expected do
      :ok
    else
      Process.sleep(1)
      await_count(expected, attempts - 1)
    end
  end
end
