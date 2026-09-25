defmodule ThistleTea.Game.World.Loader.FlareDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.PersistentArea
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  describe "load/1" do
    test "Flare has no unit impacts, while Flamestrike keeps its initial damage" do
      {caster, target_guid} = casting_scene()

      for {spell_id, expected_direct_types} <- [{1543, []}, {26_573, []}, {2120, [:school_damage]}] do
        spell = SpellLoader.load(spell_id)
        cast = Cast.new(spell, Target.at({3.0, 0.0, 0.0}), 1_000)
        result = Casting.complete(caster, cast, 1_000)
        areas = Enum.filter(result.internal.events, &is_struct(&1, Effects.SpawnAreaEffect))
        deliveries = Enum.filter(result.internal.events, &is_struct(&1, Effects.DeliverSpell))
        assert length(areas) == Enum.count(spell.effects, &(&1.type == :persistent_area_aura))

        if expected_direct_types == [] do
          assert deliveries == []
        else
          assert [%Effects.DeliverSpell{target_guid: ^target_guid, spell: direct}] = deliveries
          assert Enum.map(direct.effects, & &1.type) == expected_direct_types
        end

        assert %Effects.SpellGo{hit_guids: hits} = Enum.find(result.internal.events, &is_struct(&1, Effects.SpellGo))
        if spell_id == 1543, do: assert(hits == []), else: assert(hits == [target_guid])
      end
    end

    test "Flare reveals both concealment types and protects only for its source lifetime" do
      flare = SpellLoader.load(1543)
      assert Spell.attribute?(flare, :immunity_purges_effect)
      assert Spell.harmful?(flare)

      effects = Enum.filter(flare.effects, &(&1.type == :persistent_area_aura))
      assert [%Effect{aura: :dispel_immunity, misc_value: 5}, %Effect{aura: :dispel_immunity, misc_value: 6}] = effects

      target = target()
      stealth = SpellLoader.load(1784)
      invisibility = SpellLoader.load(66)
      {target, _} = Aura.apply_spell(target, 1, 60, stealth, 0)
      {target, _} = Aura.apply_spell(target, 1, 60, invisibility, 0)
      assert Bitwise.band(target.player.field_bytes2_flags, 0x60) == 0x60

      target =
        Enum.reduce(effects, target, fn effect, target ->
          spell = %{flare | effects: [%{effect | type: :apply_aura, semantic: nil}]}

          context = %CastContext{
            caster_guid: 2,
            caster_level: 60,
            target_hostile?: true,
            spell: spell,
            persistent_area: %PersistentArea{
              guid: 100 + effect.index,
              position: {target.internal.world, 0.0, 0.0, 0.0},
              radius: effect.radius_yards,
              started_at: 100,
              expires_at: 100 + flare.duration_ms
            }
          }

          {target, _} = Aura.apply_spell(target, context, spell, 100)
          target
        end)

      assert [%Holder{spell: %Spell{id: 1543}, auras: [_, _]}] = target.unit.auras
      assert Bitwise.band(target.player.field_bytes2_flags, 0x60) == 0
      assert Bitwise.band(target.unit.vis_flag, 0x02) == 0

      for spell <- [stealth, invisibility] do
        {blocked, _} = Aura.apply_spell(target, 1, 60, spell, 200)
        refute Aura.has_spell?(blocked, spell.id)
      end

      {target, _} = Aura.tick(target, 100 + flare.duration_ms)
      assert target.unit.auras == []

      for spell <- [stealth, invisibility] do
        {restored, _} = Aura.apply_spell(target, 1, 60, spell, 101 + flare.duration_ms)
        assert Aura.has_spell?(restored, spell.id)
      end
    end
  end

  defp target do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 1_000, max_health: 1_000, auras: []},
      player: %Player{},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp casting_scene do
    guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    target_guid = Guid.runtime(:mob, 721)
    world = WorldRef.instance(0, System.unique_integer([:positive]))
    caster = target()

    caster = %{
      caster
      | object: %{caster.object | guid: guid},
        unit: %{caster.unit | power1: 1_000, max_power1: 1_000, power_type: 0},
        internal: %{caster.internal | world: world}
    }

    Metadata.put(guid, %{alive?: true, unit_flags: 0, faction_template: %FactionTemplate{id: 1, faction_group: 1}})

    Metadata.put(target_guid, %{
      alive?: true,
      unit_flags: 0,
      level: 1,
      faction_template: %FactionTemplate{id: 17, faction_group: 8, enemy_group: 1}
    })

    SpatialHash.insert(:mobs, target_guid, world, 3.0, 0.0, 0.0)

    on_exit(fn ->
      SpatialHash.remove(:mobs, target_guid)
      Metadata.delete(guid)
      Metadata.delete(target_guid)
    end)

    {caster, target_guid}
  end
end
