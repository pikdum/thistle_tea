defmodule ThistleTea.Game.Entity.Server.Mob.MovementInformTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.AIEvent
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.SmsgMonsterMove
  alias ThistleTea.Game.World
  alias ThistleTea.Game.WorldRef

  describe "movement completion" do
    test "an observer arriving during the move retains its final facing" do
      entity = mob(nil)
      on_exit(fn -> World.stop_entity(entity.object.guid) end)
      {:ok, pid} = World.start_entity(entity)

      step = %ScriptStep{
        command: :move_to,
        datalong3: 4,
        datalong4: 2,
        datalong2: 5_000,
        dataint: 1,
        position: {10.0, 0.0, 0.0, 1.5}
      }

      Entity.start_script(entity.object.guid, [step], 0)
      GenServer.cast(pid, {:send_update_to, self()})

      assert_receive {:"$gen_cast", {:send_packet, %SmsgMonsterMove{move_type: 4, angle: 1.5, duration: duration}}},
                     1_000

      assert duration > 0 and duration <= 5_000
    end

    test "scripted evade runs the shared combat reset and its callbacks" do
      event = %AIEvent{event_type: :evade, actions: [[%ScriptStep{command: :stand_state, datalong: 7}]]}
      entity = mob(event)

      entity = %{
        entity
        | unit: %{entity.unit | health: 5, target: 5},
          internal: %{
            entity.internal
            | in_combat: true,
              threat: %{5 => 100.0},
              spawn: %{entity.internal.spawn | position: {0.0, 0.0, 0.0}}
          }
      }

      assert {:noreply, reset, {:continue, :maybe_broadcast}} = MobServer.handle_cast(:enter_evade, entity)
      refute reset.internal.in_combat
      assert reset.internal.threat == %{}
      assert reset.unit.target == 0
      assert reset.unit.health == reset.unit.max_health
      assert reset.unit.stand_state == 7
      dead = %{entity | unit: %{entity.unit | health: 0}}
      assert {:noreply, ^dead, {:continue, :maybe_broadcast}} = MobServer.handle_cast(:enter_evade, dead)
    end

    test "an idle owner wakes at arrival and executes the EventAI action" do
      event = %AIEvent{
        event_type: :movement_inform,
        param1: 9,
        param2: 1,
        actions: [[%ScriptStep{command: :stand_state, datalong: 7}]]
      }

      mob = mob(event)
      on_exit(fn -> World.stop_entity(mob.object.guid) end)
      {:ok, pid} = World.start_entity(mob)

      step = %ScriptStep{
        command: :move_to,
        datalong3: 4,
        datalong4: 2,
        datalong2: 100,
        dataint: 1,
        position: {1.0, 0.0, 0.0, 1.5}
      }

      Entity.start_script(mob.object.guid, [step], 0)
      assert await_arrival(pid, 200)
      arrived = :sys.get_state(pid)
      assert arrived.movement_block.position == {1.0, 0.0, 0.0, 1.5}
      assert arrived.internal.movement_options == nil
      assert World.position(mob.object.guid) == {mob.internal.world, 1.0, 0.0, 0.0}
      assert Process.alive?(pid)
    end

    test "delivery uses the explicit owner context" do
      parent = self()

      owner =
        spawn(fn ->
          receive do
            message -> send(parent, {:owner, message})
          end
        end)

      effect = %Effects.MovementInform{motion_type: 9, point_id: 1}
      entity = mob(nil)
      assert EventSink.emit(entity, effect, Context.new(owner)) == entity
      assert_receive {:owner, {:"$gen_cast", {:movement_inform, 9, 1}}}
      refute_receive {:"$gen_cast", {:movement_inform, 9, 1}}

      owner =
        spawn(fn ->
          receive do
            message -> send(parent, {:owner, message})
          end
        end)

      effect = %Effects.EnterEvade{target_guid: entity.object.guid}
      assert EventSink.emit(entity, effect, Context.new(owner)) == entity
      assert_receive {:owner, {:"$gen_cast", :enter_evade}}
      refute_receive {:"$gen_cast", :enter_evade}
    end
  end

  defp await_arrival(_pid, 0), do: false

  defp await_arrival(pid, attempts) do
    if :sys.get_state(pid).unit.stand_state == 7 do
      true
    else
      Process.sleep(10)
      await_arrival(pid, attempts - 1)
    end
  end

  defp mob(event) do
    %Mob{
      object: %Object{guid: Guid.runtime(:mob, 990_403), entry: 990_403},
      unit: %Unit{health: 100, max_health: 100, level: 20, faction_template: 14, auras: [], stand_state: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, walk_speed: 2.5, run_speed: 7.0},
      internal: %Internal{
        world: WorldRef.instance(998, 1),
        creature: %Creature{stationary?: true, ai_events: if(event, do: [event], else: [])},
        spawn: %Spawn{temporary?: true, despawn_type: 7},
        spellbook: %{}
      }
    }
  end
end
