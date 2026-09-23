defmodule ThistleTea.Game.Entity.EffectResolver.TriggeredHitDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  setup [:entities]

  describe "resolve/2" do
    test "channel ticks retain caster hit inputs and the selected target after channel cleanup", %{
      caster: caster,
      target: target,
      other: other
    } do
      spell = SpellLoader.load(5143)
      spell = %{spell | effects: Spell.channel_ticked_effects(spell)}
      caster = %{caster | unit: %{caster.unit | channel_object: target.object.guid, target: other.object.guid}}

      context = %{
        CastContext.from_caster(caster, spell, caster.object.guid)
        | target_role: :caster,
          selected_target_guid: caster.object.guid
      }

      {_caster, events} = SpellEffect.receive(caster, context, spell, 1_000)
      trigger = Enum.find(events, &is_struct(&1, Effects.TriggerSpell))
      assert trigger.spell_id == 7268
      assert trigger.target_guid == target.object.guid
      assert trigger.hit_context == context
      caster = %{caster | unit: %{caster.unit | channel_object: 0}}
      :rand.seed(:exsss, {1, 1, 66})
      events = Spells.resolve(caster, trigger)
      delivery = Enum.find(events, &is_struct(&1, Effects.DeliverSpell))
      assert delivery.cast_context.spell_hit_bonus == -100
      assert delivery.cast_context.hit_outcome == :resist
      assert delivery.target_guid == target.object.guid
    end

    test "periodic holders retain the source snapshot and stop triggering after removal", %{
      caster: caster,
      target: target
    } do
      spell = %{SpellLoader.load(5143) | attributes: MapSet.new()}
      context = CastContext.from_caster(caster, spell, target.object.guid)
      {target, _events} = AuraLogic.apply_spell(target, context, spell, 0)
      assert hd(target.unit.auras).cast_context == context
      {target, events} = AuraLogic.tick(target, 1_000)
      trigger = Enum.find(events, &is_struct(&1, Effects.TriggerSpell))
      assert trigger.hit_context == context
      :rand.seed(:exsss, {1, 1, 66})
      events = Spells.resolve(target, trigger)
      assert Enum.any?(events, &match?(%Effects.DeliverSpell{cast_context: %{hit_outcome: :resist}}, &1))
      {target, _events} = AuraLogic.remove_spells(target, [spell.id], 1_100)
      {target, []} = AuraLogic.tick(target, 2_000)
      assert target.unit.auras == []
      assert AuraLogic.next_event_at(target) == nil
    end

    test "a nonbinary trigger reports its saved resist at launch and impact", %{caster: caster, target: target} do
      events = resolve(caster, target.object.guid, 133)
      guid = target.object.guid
      assert [%Effects.SpellGo{hit_guids: [], misses: [%{guid: ^guid, reason: 2}]} | _] = events
      delivery = Enum.find(events, &is_struct(&1, Effects.DeliverSpell))
      assert delivery.cast_context.hit_outcome == :resist
      refute Spell.binary?(delivery.spell)

      assert {^target, [%Effects.SpellLogMiss{reason: :resist}]} =
               SpellEffect.receive(target, delivery.cast_context, delivery.spell, 1_000)
    end

    test "successful deliveries retain the launch result when target hit modifiers change", %{
      caster: caster,
      target: target
    } do
      Metadata.update(target.object.guid, %{no_spell_defense?: true})
      events = resolve(caster, target.object.guid, 133)
      guid = target.object.guid
      assert [%Effects.SpellGo{hit_guids: [^guid], misses: []} | _] = events
      delivery = Enum.find(events, &is_struct(&1, Effects.DeliverSpell))
      Metadata.update(guid, %{no_spell_defense?: false, attacker_spell_hit_chance: [{4, -100}]})
      {damaged, effects} = SpellEffect.receive(target, delivery.cast_context, delivery.spell, 1_000)
      assert damaged.unit.health < target.unit.health
      assert Enum.any?(effects, &is_struct(&1, Effects.SpellDamage))
    end

    test "area triggers roll each target and keep separate launch lists", %{
      caster: caster,
      target: target,
      other: other
    } do
      Metadata.update(target.object.guid, %{no_spell_defense?: true})
      events = resolve(caster, target.object.guid, 1449)
      hit = target.object.guid
      miss = other.object.guid
      assert [%Effects.SpellGo{hit_guids: [^hit], misses: [%{guid: ^miss, reason: 2}]} | _] = events

      outcomes =
        for %Effects.DeliverSpell{target_guid: guid, cast_context: context} <- events,
            into: %{},
            do: {guid, context.hit_outcome}

      assert outcomes == %{hit => :hit, miss => :resist}
    end

    test "beneficial, unclassified and weapon spells bypass the magic roll", %{caster: caster, target: target} do
      for id <- [139, 2050, 78] do
        events = resolve(caster, target.object.guid, id)
        assert [%Effects.SpellGo{misses: []} | _] = events
        assert Enum.any?(events, &match?(%Effects.DeliverSpell{cast_context: %{hit_outcome: :hit}}, &1))
      end
    end

    test "caster channels retain their selected enemy without a wrapper hit roll", %{caster: caster, target: target} do
      assert [%Effects.StartTriggeredChannel{} = event] = resolve(caster, target.object.guid, 5143)
      entity = Casting.start_triggered(caster, event.spell, event.targets, 1_000, nil, event.context)
      assert Enum.sort(entity.internal.casting.resolution.hits) == Enum.sort([caster.object.guid, target.object.guid])
      assert entity.internal.casting.resolution.misses == []
      assert entity.internal.casting.resolution.followups.selected_unit_guid == target.object.guid
      assert entity.unit.channel_object == target.object.guid
    end

    test "a saved resist still allows reflection to resolve first", %{caster: caster, target: target} do
      delivery = caster |> resolve(target.object.guid, 133) |> Enum.find(&is_struct(&1, Effects.DeliverSpell))
      shield = %Holder{spell: %Spell{id: 999_802}, auras: [%Aura{type: :reflect_spells, amount: 100}]}
      target = %{target | unit: %{target.unit | auras: [shield]}}
      {unchanged, events} = SpellEffect.receive(target, delivery.cast_context, delivery.spell, 1_000)
      assert unchanged.unit.health == target.unit.health
      assert Enum.any?(events, &match?(%Effects.SpellLogMiss{reason: :reflect}, &1))
      assert Enum.any?(events, &match?(%Effects.DeliverSpell{cast_context: %{hit_outcome: :hit}}, &1))
      refute Enum.any?(events, &match?(%Effects.SpellLogMiss{reason: :resist}, &1))
    end

    test "foreign triggers match the child family mask using the original hit snapshot", %{
      caster: caster,
      target: target
    } do
      bonus = %Holder{
        spell: %Spell{id: 999_803, spell_family: 3},
        auras: [
          %Aura{type: :add_flat_modifier, misc_value: 16, amount: 100, class_mask: 1}
        ]
      }

      caster = %{caster | unit: %{caster.unit | auras: [bonus | caster.unit.auras]}}
      parent = CastContext.from_caster(caster, SpellLoader.load(5143), target.object.guid)
      assert parent.spell_hit_bonus == -100
      trigger = Effects.trigger_spell(caster.object.guid, 60, target.object.guid, 133, hit_context: parent)
      :rand.seed(:exsss, {1, 1, 66})
      events = Spells.resolve(target, trigger)
      delivery = Enum.find(events, &is_struct(&1, Effects.DeliverSpell))
      assert delivery.cast_context.spell_hit_bonus == 0
      assert delivery.cast_context.hit_outcome == :hit
      assert delivery.cast_context.caster_guid == caster.object.guid

      :rand.seed(:exsss, {1, 1, 66})
      other = Spells.resolve(target, %{trigger | spell_id: 686})

      delivery = Enum.find(other, &is_struct(&1, Effects.DeliverSpell))
      assert delivery.cast_context.spell_hit_bonus == -100
      assert delivery.cast_context.hit_outcome == :resist
    end
  end

  defp resolve(caster, target, spell_id) do
    :rand.seed(:exsss, {1, 1, 66})
    Spells.resolve(caster, Effects.trigger_spell(caster.object.guid, caster.unit.level, target, spell_id))
  end

  defp entities(_context) do
    world = WorldRef.instance(0, System.unique_integer([:positive]))
    penalty = %Holder{spell: %Spell{id: 999_801}, auras: [%Aura{type: :mod_spell_hit_chance, amount: -100}]}

    caster = %Mob{
      object: %Object{guid: Guid.runtime(:mob, 1)},
      unit: %Unit{level: 60, health: 1_000, max_health: 1_000, faction_template: 17, auras: [penalty]},
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    targets =
      for x <- [1.0, 2.0] do
        target = %Character{
          object: %Object{guid: Guid.from_low_guid(:player, System.unique_integer([:positive]))},
          unit: %Unit{level: 60, health: 1_000, max_health: 1_000, faction_template: 1, auras: []},
          internal: %Internal{world: world},
          movement_block: %MovementBlock{position: {x, 0.0, 0.0, 0.0}}
        }

        SpatialHash.insert(:players, target.object.guid, world, x, 0.0, 0.0)

        Metadata.put(target.object.guid, %{
          alive?: true,
          level: 60,
          unit_flags: 0,
          faction_template: %FactionTemplate{
            id: 1,
            faction: 1,
            flags: 72,
            faction_group: 3,
            friend_group: 2,
            enemy_group: 12
          },
          faction_can_have_reputation?: false
        })

        target
      end

    Metadata.put(caster.object.guid, %{
      alive?: true,
      level: 60,
      unit_flags: 0,
      faction_template: %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, enemy_group: 1},
      faction_can_have_reputation?: false
    })

    on_exit(fn ->
      Metadata.delete(caster.object.guid)

      for target <- targets do
        Metadata.delete(target.object.guid)
        SpatialHash.remove(:players, target.object.guid)
      end
    end)

    [target, other] = targets
    %{caster: caster, target: target, other: other}
  end
end
