defmodule ThistleTea.Game.World.Entity.WildTrapDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.AreaEffects
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Loader.Faction
  alias ThistleTea.Game.World.Loader.GameObject, as: GameObjectLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Spell.SpellTargetResolver
  alias ThistleTea.Test.Unique

  @moduletag :dbc_db

  setup [:spell_chains]

  describe "trap activation" do
    test "owned Frost Trap creates ticking areas with complete caster snapshots" do
      owner_guid = Guid.from_low_guid(:player, Unique.integer())
      target_guid = Guid.from_low_guid(:player, Unique.integer())
      {:ok, _} = Entity.register(target_guid)

      target = %Character{
        object: %Object{guid: target_guid},
        internal: %Internal{world: WorldRef.open(999)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      World.update_position(target)
      Metadata.put(owner_guid, Map.merge(Faction.metadata(14), %{alive?: true, pvp?: true}))
      Metadata.put(target_guid, Map.merge(Faction.metadata(1), %{alive?: true, pvp?: true}))

      template = %GameObjectTemplate{
        entry: 950_005,
        type: 6,
        size: 1.0,
        faction: 14,
        flags: 0,
        data: [0, 50, 0, 13_810, 1, 0, 0, 0]
      }

      trap = GameObject.build_summoned(template, target.internal.world, {0.0, 0.0, 0.0, 0.0}, summoned_by: owner_guid)
      {:ok, pid} = World.start_entity(trap)

      on_exit(fn ->
        World.stop_entity(trap.object.guid)
        Enum.each(AreaEffects.pids(owner_guid, 13_810), &World.stop_entity/1)
        World.remove_position(target)
        Metadata.delete(owner_guid)
        Metadata.delete(target_guid)
      end)

      send(pid, {:script_activate_object, target_guid})

      for index <- [0, 1] do
        assert_receive {:"$gen_cast",
                        {:receive_spell, %CastContext{caster_guid: ^owner_guid, persistent_area: area},
                         %Spell{id: 13_810, effects: [%{index: ^index}]}}},
                       1_000

        assert area.radius == 10.0
      end

      assert length(AreaEffects.pids(owner_guid, 13_810)) == 2
    end

    test "a world-loaded campfire discovers a nearby player and delivers environmental fire" do
      player_guid = Guid.from_low_guid(:player, Unique.integer())
      {:ok, _} = Entity.register(player_guid)

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
        GameObjectLoader.build(%Mangos.GameObject{
          guid: Unique.integer(),
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
      player_guid = Guid.from_low_guid(:player, Unique.integer())
      {:ok, _} = Entity.register(player_guid)

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

  defp spell_chains(_context) do
    for id <- [7897, 13_810, 25_656] do
      key = {:chain, id}
      previous = :ets.lookup(SpellChain, key)
      :ets.insert(SpellChain, {key, nil})

      on_exit(fn ->
        :ets.delete(SpellChain, key)
        :ets.insert(SpellChain, previous)
      end)
    end

    :ok
  end
end
