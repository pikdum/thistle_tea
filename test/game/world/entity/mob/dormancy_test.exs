defmodule ThistleTea.Game.World.Entity.Mob.DormancyTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.AIEvent
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.Combat.Proximity.Announcement
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.Mob, as: MobServer
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Test.Unique

  describe "handle_continue/2" do
    test "an idle creature with nothing to maintain keeps no timer" do
      assert {:noreply, idle} = MobServer.handle_continue(:maybe_broadcast, mob())
      assert idle.internal.ai_tick_ref == nil
    end

    test "re-arms the timer when upkeep needs a wake" do
      mob = mob()
      injured = %{mob | unit: %{mob.unit | health: 40}}

      assert {:noreply, woken} = MobServer.handle_continue(:maybe_broadcast, injured)
      assert is_reference(woken.internal.ai_tick_ref)
      Process.cancel_timer(woken.internal.ai_tick_ref)
    end
  end

  describe "handle_info/2" do
    test "an announcer in sight wakes the creature at its next EventAI slot" do
      now = Time.now()
      blackboard = Blackboard.put_next_at(Blackboard.new(), :next_eventai_at, 400, now)
      creature = %Creature{detection_range: 20.0, ai_events: [%AIEvent{event_type: :ooc_los, param2: 20}]}
      mob = mob()
      greeter = %{mob | internal: %{mob.internal | blackboard: blackboard, creature: creature}}
      announcement = %Announcement{guid: 1, world: WorldRef.open(0), position: {5.0, 0.0, 0.0}, level: 10}

      assert {:noreply, woken} = MobServer.handle_info({:proximity, announcement}, greeter)
      assert remaining = Process.read_timer(woken.internal.ai_tick_ref)
      assert remaining > 200 and remaining <= 400
      Process.cancel_timer(woken.internal.ai_tick_ref)

      assert {:noreply, unchanged} =
               MobServer.handle_info({:proximity, %{announcement | position: {60.0, 0.0, 0.0}}}, greeter)

      assert unchanged.internal.ai_tick_ref == nil
    end
  end

  defp mob do
    guid = Guid.from_low_guid(:mob, 1, Unique.integer())
    Metadata.put(guid, %{alive?: true})
    on_exit(fn -> Metadata.delete(guid) end)

    %Mob{
      object: %Object{guid: guid},
      unit: %Unit{level: 10, health: 100, max_health: 100, flags: 0, auras: []},
      internal: %Internal{world: WorldRef.open(0), in_combat: false, creature: %Creature{detection_range: 20.0}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end
end
