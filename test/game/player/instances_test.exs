defmodule ThistleTea.Game.Player.InstancesTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.HomeBind
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Instances
  alias ThistleTea.Game.World.Loader.AreaTrigger
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.WorldRef

  describe "restore/3" do
    test "returns to the home bind when the old instance refuses admission" do
      character = %Character{
        internal: %Internal{
          world: WorldRef.instance(309, 1),
          area: 100,
          home_bind: %HomeBind{map_id: 0, area_id: 12, position: {1.0, 2.0, 3.0}}
        },
        movement_block: %MovementBlock{position: {50.0, 60.0, 70.0, 1.0}}
      }

      for reason <- [:instance_full, :raid_group_required, :too_many_instances, :instance_unavailable] do
        restored = Instances.restore(character, 1, enter: fn 309, 1 -> {:error, reason} end)
        assert restored.internal.world == WorldRef.open(0)
        assert restored.internal.area == 12
        assert restored.movement_block.position == {1.0, 2.0, 3.0, 0.0}
      end

      world = WorldRef.instance(309, 2)
      restored = Instances.restore(character, 1, enter: fn 309, 1 -> {:ok, world} end)
      assert restored.internal.world == world
      assert restored.movement_block == character.movement_block
    end
  end

  describe "teleport admission" do
    test "rejects a raid transfer without moving or disconnecting the player" do
      map = 900_001
      :ets.insert(AreaTrigger, {{:instance_map, map}, true})
      :ets.insert(MapTemplate, {map, 2, nil})

      on_exit(fn ->
        :ets.delete(AreaTrigger, {:instance_map, map})
        :ets.delete(MapTemplate, map)
      end)

      guid = System.unique_integer([:positive])
      state = %State{ready: true, guid: guid, character: %Character{internal: %Internal{world: WorldRef.open(0)}}}
      count = InstanceSystem.count()
      assert PlayerServer.handle_cast({:start_teleport, 1.0, 2.0, 3.0, 0.0, map}, state) == {:noreply, state}
      assert InstanceSystem.count() == count
      assert InstanceSystem.info(guid).current == nil
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgRaidGroupOnly{delay_ms: 0, reason: :required}}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgNewWorld{}}}
    end
  end

  describe "reject/1" do
    test "projects the distinct vanilla admission failures" do
      for reason <- [:instance_full, :too_many_instances, :instance_unavailable] do
        Instances.reject(reason)
        assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgTransferAborted{reason: ^reason}}}
      end
    end
  end
end
