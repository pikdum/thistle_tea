defmodule ThistleTea.Game.Player.DeadminesTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Instance.Copy
  alias ThistleTea.Game.Player.Deadmines
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.InstanceData
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:cannon]

  describe "validate_target/2" do
    test "requires a nearby cannon in the same unbreached dungeon copy", context do
      assert :ok = Deadmines.validate_target(context.state, context.guid)
      refute_valid(context, WorldRef.instance(36, context.world.instance_id + 1), 2.0)
      refute_valid(context, context.world, 50.0)
      refute_valid(context, WorldRef.open(36), 2.0)
      SpatialHash.remove(:game_objects, context.guid)
      assert {:error, :bad_targets} = Deadmines.validate_target(context.state, context.guid)
    end

    test "rejects dead players and already fired cannons", context do
      state = context.state
      dead = put_in(state.character.unit.health, 0)
      assert {:error, :bad_targets} = Deadmines.validate_target(dead, context.guid)
      InstanceData.publish(%Copy{world: context.world, script_name: "instance_deadmines", data: %{1 => 1}})
      assert {:error, :bad_targets} = Deadmines.validate_target(context.state, context.guid)
      assert Deadmines.fire(context.state, context.guid) == context.state
    end
  end

  describe "validate_cast/4" do
    test "requires the owned gunpowder item and the cannon target", context do
      powder = ItemStore.create(%ItemTemplate{entry: 5_397}, owner: context.state.guid)
      on_exit(fn -> ItemStore.delete(powder.object.guid) end)
      spell = %Spell{id: 6_250}
      target = Target.object(context.guid)

      assert {:error, :item_not_found} = Deadmines.validate_cast(context.state, spell, target, powder.object.guid)
      state = context.state
      state = put_in(state.character.player.inv1, powder.object.guid)
      assert :ok = Deadmines.validate_cast(state, spell, target, powder.object.guid)
      assert {:error, :item_not_found} = Deadmines.validate_cast(state, spell, target, nil)
      assert {:error, :bad_targets} = Deadmines.validate_cast(state, spell, Target.none(), powder.object.guid)
    end
  end

  defp refute_valid(context, world, x) do
    SpatialHash.update(:game_objects, context.guid, world, x, 0.0, 0.0)
    assert {:error, :bad_targets} = Deadmines.validate_target(context.state, context.guid)
  end

  defp cannon(_context) do
    id = System.unique_integer([:positive])
    world = WorldRef.instance(36, id)
    guid = Guid.from_low_guid(:game_object, 16_398, id)

    character = %Character{
      object: %Object{guid: id},
      unit: %Unit{health: 100},
      player: %Player{},
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    SpatialHash.update(:game_objects, guid, world, 2.0, 0.0, 0.0)
    InstanceData.publish(%Copy{world: world, script_name: "instance_deadmines"})

    on_exit(fn ->
      SpatialHash.remove(:game_objects, guid)
      InstanceData.remove(world)
    end)

    %{state: %{guid: id, character: character}, world: world, guid: guid}
  end
end
