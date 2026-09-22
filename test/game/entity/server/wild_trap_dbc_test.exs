defmodule ThistleTea.Game.Entity.Server.WildTrapDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
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
    test "a world-loaded campfire discovers a nearby player and delivers environmental fire" do
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      Entity.register(player_guid)

      player = %Character{
        object: %Object{guid: player_guid},
        player: %Player{flags: 0},
        unit: %Unit{health: 100, max_health: 100, level: 60, auras: [], fire_resistance: 0},
        internal: %Internal{world: WorldRef.open(999)},
        movement_block: %MovementBlock{position: {5.0, 0.0, 0.0, 0.0}}
      }

      World.update_position(player)
      Metadata.put(player_guid, Map.put(Faction.metadata(1), :alive?, true))

      template = %Mangos.GameObjectTemplate{
        entry: 2061,
        type: 6,
        size: 1.0,
        faction: 14,
        flags: 0,
        data2: 2,
        data3: 7897,
        data5: 3
      }

      trap =
        GameObject.build(%Mangos.GameObject{
          guid: System.unique_integer([:positive]),
          id: 2061,
          map: 999,
          game_object_template: template
        })

      {:ok, pid} = World.start_entity(trap)
      guid = trap.object.guid

      on_exit(fn ->
        World.stop_entity(guid)
        World.remove_position(player)
        Metadata.delete(player_guid)
      end)

      refute_receive {:"$gen_cast", {:receive_spell, _, _}}, 250
      player = %{player | movement_block: %{player.movement_block | position: {0.0, 0.0, 0.0, 0.0}}}
      World.update_position(player)

      assert_receive {:"$gen_cast",
                      {:receive_spell, %CastContext{caster_guid: ^guid} = context, %Spell{id: 7897} = spell}},
                     1_000

      {burned, events} = SpellEffect.receive(player, context, spell, 1000)
      assert events == []
      assert burned.unit.health in 85..90

      assert [%Effects.EnvironmentalDamage{type: :fire, damage: damage}] =
               Enum.filter(burned.internal.events, &is_struct(&1, Effects.EnvironmentalDamage))

      assert damage == 100 - burned.unit.health
      refute burned.internal.in_combat
      assert Process.alive?(pid)
    end

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

      trap = GameObject.build_summoned(template, player.internal.world, {0.0, 0.0, 0.0, 0.0}, level: 0)
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

      assert_receive {:"$gen_cast",
                      {:receive_spell, %CastContext{caster_guid: ^guid, caster_level: 60}, %Spell{id: 25_656}}},
                     1_000

      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
      refute_receive {:"$gen_cast", {:receive_spell, _, %Spell{id: 25_656}}}
    end
  end
end
