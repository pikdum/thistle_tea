defmodule ThistleTea.Game.Entity.Server.ScriptDeliveryTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.ScriptDelivery
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.WorldRef

  describe "start/3" do
    test "recipient death fails the original receipt" do
      {receiver, guid} = receiver()
      world = WorldRef.open(0)
      :ok = ScriptDelivery.start(Context.new(self()), {7, 3, world}, effect(guid))
      assert_receive {:request, request}
      monitor = Process.monitor(request.reply_to)
      Process.exit(receiver, :kill)
      assert_receive {:script_resume, 7, 3, ^world, :failed}
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
      refute_receive {:script_resume, 7, 3, ^world, _}
    end

    test "caller death stops delivery and invalidates a queued request" do
      {_receiver, guid} = receiver()

      owner =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      on_exit(fn -> Process.exit(owner, :kill) end)
      :ok = ScriptDelivery.start(Context.new(owner), {7, 1, WorldRef.open(0)}, effect(guid))
      assert_receive {:request, request}
      monitor = Process.monitor(request.reply_to)
      send(owner, :stop)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
      refute Process.alive?(request.reply_to)
    end

    test "duplicate results produce exactly one completion" do
      {_receiver, guid} = receiver()
      world = WorldRef.open(0)
      :ok = ScriptDelivery.start(Context.new(self()), {7, 2, world}, effect(guid))
      assert_receive {:request, request}
      ScriptDelivery.reply(request, :terminated)
      ScriptDelivery.reply(request, :continue)
      assert_receive {:script_resume, 7, 2, ^world, :terminated}
      refute_receive {:script_resume, 7, 2, ^world, _}
    end
  end

  defp effect(guid), do: Effects.forward_script_steps(guid, [%ScriptStep{command: :stand_state}], 0)

  defp receiver do
    owner = self()
    guid = Guid.runtime(:mob, 15_694)

    pid =
      spawn(fn ->
        Entity.register(guid)
        send(owner, {:ready, self()})

        receive do
          {:script_command, request} ->
            send(owner, {:request, request})

            receive do
              :stop -> :ok
            end
        end
      end)

    on_exit(fn -> Process.exit(pid, :kill) end)
    assert_receive {:ready, ^pid}
    {pid, guid}
  end
end
