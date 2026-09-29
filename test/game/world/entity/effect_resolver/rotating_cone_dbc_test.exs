defmodule ThistleTea.Game.World.Entity.EffectResolver.RotatingConeDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.DBC
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cone
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.EffectResolver.Spells
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.Spell.SpellTargetResolver

  @moduletag :dbc_db

  setup [:ring]

  describe "resolve/3" do
    test "Lava Breath and Sand Blast use their cone instead of the selected enemy", %{caster: caster, ring: ring} do
      for id <- [19_272, 26_102] do
        spell = SpellLoader.load(id)
        assert spell.cone == %Cone{}
        assert Enum.all?(spell.effects, &(&1.implicit_target_a == :aoe_enemy_in_cone))
        assert Spell.area_of_effect?(spell)

        assert SpellTargetResolver.resolve(caster, spell, Target.unit(Enum.at(ring, 4).object.guid)) ==
                 [hd(ring).object.guid]
      end
    end

    test "each whirl child selects a rotated 120-degree arc with world and distance filtering", context do
      %{caster: caster, ring: ring} = context
      nearby = hd(ring)
      publish(%{nearby | object: %Object{guid: player_guid()}, unit: %{nearby.unit | health: 0}})

      foreign = %{nearby | object: %Object{guid: player_guid()}, internal: %Internal{world: WorldRef.instance(0, 0)}}
      publish(foreign)
      publish(character(caster.internal.world, 0, 101.0))
      publish(%{caster | object: %Object{guid: Guid.runtime(:mob, 1)}})

      spells = [24_820, 24_821, 24_822, 24_823, 24_835, 24_836, 24_837, 24_838]

      for {id, step} <- Enum.with_index(spells) do
        spell = SpellLoader.load(id)
        assert spell.cone.degrees == 120
        assert_in_delta spell.cone.offset_radians, step * :math.pi() / 4, 0.00001

        expected =
          [Integer.mod(step - 1, 8), step, rem(step + 1, 8)]
          |> Enum.map(&Enum.at(ring, &1).object.guid)
          |> Enum.sort()

        actual = SpellTargetResolver.resolve(caster, spell, Target.unit(Enum.at(ring, rem(step + 4, 8)).object.guid))
        assert Enum.sort(actual) == expected
      end
    end
  end

  describe "periodic trigger resolution" do
    test "a complete rotation launches and damages only the three current cone recipients", context do
      %{caster: caster, ring: ring} = context
      parent = SpellLoader.load(24_834)
      assert parent.duration_ms == -1
      assert [%{aura: :periodic_trigger_spell, amplitude_ms: 5_000, trigger_spell_id: nil}] = parent.effects
      {caster, _events} = Aura.apply_spell(caster, caster.object.guid, 60, parent, 0)

      Enum.reduce(1..8, caster, fn tick, current ->
        {current, events} = Aura.tick(current, tick * 5_000)
        [trigger] = Enum.filter(events, &is_struct(&1, Effects.TriggerSpell))
        events = Spells.resolve(current, trigger)
        deliveries = Enum.filter(events, &is_struct(&1, Effects.DeliverSpell))

        expected =
          [Integer.mod(tick - 1, 8), rem(tick, 8), rem(tick + 1, 8)]
          |> Enum.map(&Enum.at(ring, &1).object.guid)
          |> Enum.sort()

        assert Enum.sort(Enum.map(deliveries, & &1.target_guid)) == expected
        assert [%Effects.SpellGo{hit_guids: hits, misses: []} | _] = events
        assert Enum.sort(hits) == expected

        for delivery <- deliveries do
          target = Enum.find(ring, &(&1.object.guid == delivery.target_guid))
          {damaged, feedback} = SpellEffect.receive(target, delivery.cast_context, delivery.spell, tick * 5_000)
          assert damaged.unit.health < target.unit.health
          assert Enum.any?(feedback, &is_struct(&1, Effects.SpellDamage))
        end

        current
      end)
    end
  end

  defp ring(_context) do
    world = WorldRef.instance(0, System.unique_integer([:positive]))

    caster =
      %Mob{
        object: %Object{guid: Guid.runtime(:mob, 1)},
        unit: %Unit{health: 10_000, max_health: 10_000, level: 60, auras: []},
        internal: %Internal{world: world},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, :math.pi() / 8}}
      }
      |> publish()

    ring = for step <- 0..7, do: world |> character(step, 20.0) |> publish()
    %{caster: caster, ring: ring}
  end

  defp character(world, step, distance) do
    angle = :math.pi() / 8 + step * :math.pi() / 4

    %Character{
      object: %Object{guid: player_guid()},
      unit: %Unit{health: 10_000, max_health: 10_000, level: 60, auras: []},
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {distance * :math.cos(angle), distance * :math.sin(angle), 0.0, 0.0}}
    }
  end

  defp player_guid, do: Guid.from_low_guid(:player, System.unique_integer([:positive]))

  defp publish(entity) do
    guid = entity.object.guid
    {x, y, z, _o} = entity.movement_block.position
    table = if is_struct(entity, Character), do: :players, else: :mobs
    faction = if table == :players, do: 1, else: 17
    SpatialHash.insert(table, guid, entity.internal.world, x, y, z)

    Metadata.put(guid, %{
      alive?: entity.unit.health > 0,
      level: entity.unit.level,
      unit_flags: 0,
      no_spell_defense?: true,
      faction_can_have_reputation?: false,
      faction_template: %DBC.FactionTemplate{
        id: faction,
        faction: faction,
        enemies_0: if(faction == 1, do: 17, else: 1)
      }
    })

    on_exit(fn ->
      SpatialHash.remove(table, guid)
      Metadata.delete(guid)
    end)

    entity
  end
end
