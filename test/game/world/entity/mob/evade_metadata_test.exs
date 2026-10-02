defmodule ThistleTea.Game.World.Entity.Mob.EvadeMetadataTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.Mob, as: MobServer
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Test.Unique

  describe "handle_continue/2" do
    test "publishes evading while the creature walks home" do
      mob = returning_home(mob(), true)

      assert {:noreply, mob} = MobServer.handle_continue(:maybe_broadcast, mob)
      assert %{evading?: true} = Metadata.query(mob.object.guid, [:evading?])
      cancel_tick(mob)
    end

    test "clears evading once the creature is home, without a pending broadcast" do
      mob = mob()
      Metadata.update(mob.object.guid, %{evading?: true})

      assert {:noreply, mob} = MobServer.handle_continue(:maybe_broadcast, returning_home(mob, false))
      assert %{evading?: false} = Metadata.query(mob.object.guid, [:evading?])
      cancel_tick(mob)
    end
  end

  defp returning_home(%Mob{internal: internal} = mob, returning?) do
    blackboard = Blackboard.new()
    blackboard = %{blackboard | navigation: %{blackboard.navigation | returning_home?: returning?}}
    %{mob | internal: %{internal | blackboard: blackboard}}
  end

  defp cancel_tick(%Mob{internal: %Internal{ai_tick_ref: ref}}) when is_reference(ref), do: Process.cancel_timer(ref)
  defp cancel_tick(_mob), do: :ok

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
