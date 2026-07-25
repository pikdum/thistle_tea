defmodule ThistleTea.Game.Entity.Logic.AI.BT.PetTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet, as: PetBT
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @now 10_000

  describe "follow_owner/3" do
    test "stays put while a stationary owner turns in place" do
      owner_guid = stationary_owner(orientation: :math.pi())
      state = pet_beside_owner(owner_guid)

      assert {{:running, _delay}, turned, %Blackboard{}} = PetBT.follow_owner(state, %Blackboard{}, @now)
      assert turned.movement_block.position == state.movement_block.position
      assert turned.internal.events == []
    end

    test "despawns when the owner is gone" do
      owner_guid = Guid.from_low_guid(:player, :erlang.unique_integer([:positive]))
      state = pet_beside_owner(owner_guid)

      assert {:success, despawned, %Blackboard{}} = PetBT.follow_owner(state, %Blackboard{}, @now)
      assert [%Effects.DespawnSelf{}] = despawned.internal.events
    end
  end

  defp stationary_owner(opts) do
    guid = Guid.from_low_guid(:player, :erlang.unique_integer([:positive]))
    SpatialHash.update(:players, guid, world(), 0.0, 0.0, 0.0)

    Metadata.put(guid, %{
      orientation: Keyword.fetch!(opts, :orientation),
      bounding_radius: Unit.default_bounding_radius()
    })

    on_exit(fn ->
      SpatialHash.remove(:players, guid)
      Metadata.delete(guid)
    end)

    guid
  end

  defp pet_beside_owner(owner_guid) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:pet, 1, :erlang.unique_integer([:positive]))},
      unit: %Unit{bounding_radius: Unit.default_bounding_radius()},
      internal: %Internal{
        world: world(),
        pet: %Internal.Pet{owner_guid: owner_guid, command_state: :follow}
      },
      movement_block: %MovementBlock{position: {0.0, 2.0, 0.0, 0.0}, run_speed: 7.0}
    }
  end

  defp world, do: %WorldRef{map_id: 0}
end
