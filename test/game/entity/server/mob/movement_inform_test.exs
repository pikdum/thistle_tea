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
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.WorldRef

  describe "movement completion" do
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
