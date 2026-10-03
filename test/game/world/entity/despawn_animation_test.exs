defmodule ThistleTea.Game.World.Entity.DespawnAnimationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Totem
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.DynamicObject
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message.SmsgGameobjectDespawnAnim
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.DynamicObject, as: DynamicObjectServer
  alias ThistleTea.Game.World.Entity.Mob, as: MobServer
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Test.Unique

  setup [:watcher]

  describe "totems" do
    test "play their despawn animation as they leave", %{world: world} do
      guid = Guid.runtime(:mob, 5925)

      totem = %Mob{
        object: %Object{guid: guid},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}},
        internal: %Internal{world: world, totem: %Totem{owner_guid: Unique.integer()}}
      }

      assert {:stop, :normal, ^totem} = MobServer.handle_info(:totem_stop, totem)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgGameobjectDespawnAnim{guid: ^guid}, _opts}}
    end
  end

  describe "dynamic objects" do
    test "play their despawn animation as they go", %{world: world} do
      guid = Unique.integer()

      dynamic = %DynamicObject{
        object: %Object{guid: guid},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}},
        internal: %Internal{world: world}
      }

      DynamicObjectServer.terminate(:normal, %{entity: dynamic, farsight_owner_guid: nil})
      assert_receive {:"$gen_cast", {:send_packet, %SmsgGameobjectDespawnAnim{guid: ^guid}, _opts}}
    end
  end

  defp watcher(_context) do
    map_id = Unique.integer()
    watcher = Unique.integer()
    {:ok, _} = Entity.register(watcher)
    SpatialHash.update(:players, watcher, map_id, 1.0, 2.0, 3.0)
    on_exit(fn -> SpatialHash.remove(:players, watcher) end)
    %{world: WorldRef.open(map_id)}
  end
end
