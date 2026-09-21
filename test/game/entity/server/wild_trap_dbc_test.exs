defmodule ThistleTea.Game.Entity.Server.WildTrapDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Faction
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  describe "trap activation" do
    test "ownerless area traps deliver once with the game object as caster" do
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      Entity.register(player_guid)

      player = %Character{
        object: %Object{guid: player_guid},
        internal: %Internal{world: WorldRef.open(999)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      World.update_position(player)
      Metadata.put(player_guid, Map.put(Faction.metadata(1), :alive?, true))

      template = %GameObjectTemplate{
        entry: 950_004,
        type: 6,
        size: 1.0,
        faction: 14,
        flags: 0,
        data: [0, 0, 0, 25_656, 1, 0, 0, 0]
      }

      trap = GameObject.build_summoned(template, player.internal.world, {0.0, 0.0, 0.0, 0.0})
      {:ok, pid} = World.start_entity(trap)
      guid = trap.object.guid
      ref = Process.monitor(pid)

      caster = %{object: trap.object, unit: %{level: 1}, internal: trap.internal, movement_block: trap.movement_block}
      assert SpellTargetResolver.resolve(caster, SpellLoader.load(25_656), Target.unit(player_guid)) == [player_guid]

      on_exit(fn ->
        World.stop_entity(guid)
        World.remove_position(player)
        Metadata.delete(player_guid)
      end)

      send(pid, {:script_activate_object, player_guid})
      send(pid, {:script_activate_object, player_guid})
      assert_receive {:"$gen_cast", {:receive_spell, %CastContext{caster_guid: ^guid}, %Spell{id: 25_656}}}, 1_000
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
      refute_receive {:"$gen_cast", {:receive_spell, _, %Spell{id: 25_656}}}
    end
  end
end
