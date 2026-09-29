defmodule ThistleTea.Game.World.Spell.SpellLocationsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.CastValidation
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.LocationTargets
  alias ThistleTea.Game.Core.Spell.LocationTargets.Selection
  alias ThistleTea.Game.Core.Spell.ObjectTargets
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.Spell.UnitTargets
  alias ThistleTea.Game.Core.Spell.UnitTargets.Selector
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message.SmsgCastResult
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EffectResolver
  alias ThistleTea.Game.World.Entity.GameObject, as: GameObjectServer
  alias ThistleTea.Game.World.Entity.Player.Spellcasting
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Spell.SpellLocations
  alias ThistleTea.Game.World.Spell.SpellRequirements
  alias ThistleTea.Game.World.Spell.SpellTargetResolver

  setup [:caster]

  describe "resolve/4" do
    test "chooses a nearby creature and replaces supplied coordinates", %{caster: caster, spell: spell} do
      near = spawn_mob(caster, 100, {2.0, +0.0, +0.0})
      far = spawn_mob(caster, 100, {5.0, +0.0, +0.0})
      targets = Target.at({200.0, +0.0, +0.0})
      locations = SpellLocations.resolve(caster, spell, targets)
      assert %Selection{guid: near.object.guid, position: {2.0, +0.0, +0.0}, kind: :unit} == locations.by_effect[0]
      assert LocationTargets.apply(targets, locations).destination_location == {2.0, +0.0, +0.0}
      selected = SpellLocations.resolve(caster, spell, Target.unit(far.object.guid))
      assert selected.by_effect[0].guid == far.object.guid
    end

    test "compares creature and object locations while preferring an eligible selected unit", context do
      %{caster: caster, spell: spell} = context
      object = spawn_object(caster, 200, {2.0, +0.0, +0.0})
      unit = spawn_mob(caster, 100, {5.0, +0.0, +0.0})
      spell = %{spell | object_targets: [%ObjectTargets.Selector{entry: 200}]}
      assert SpellLocations.resolve(caster, spell, Target.none()).by_effect[0].guid == object
      assert SpellLocations.resolve(caster, spell, Target.unit(unit.object.guid)).by_effect[0].guid == unit.object.guid
      closer = spawn_mob(caster, 100, {0.5, +0.0, +0.0})
      assert SpellLocations.resolve(caster, spell, Target.none()).by_effect[0].guid == closer.object.guid
    end

    test "filters corpses, conditions and inverse masks by effect", %{caster: caster, spell: spell} do
      spawn_mob(caster, 100, {1.0, +0.0, +0.0}, health: 0)
      corpse = spawn_mob(caster, 100, {4.0, +0.0, +0.0}, health: 0, level: 61)
      living = spawn_mob(caster, 100, {2.0, +0.0, +0.0})
      condition = %Condition{entry: 900_046, type: :level, value1: 61, value2: 0}

      spell = %{
        spell
        | effects: [hd(spell.effects), %{hd(spell.effects) | index: 1}],
          unit_targets: [
            %Selector{entry: 100, inverse_effect_mask: 2},
            %Selector{entry: 100, alive?: false, condition: condition, inverse_effect_mask: 1}
          ]
      }

      locations = SpellLocations.resolve(caster, spell, Target.none())
      assert locations.by_effect[0].guid == living.object.guid
      assert locations.by_effect[1].guid == corpse.object.guid
      assert LocationTargets.apply(Target.none(), locations).destination_location == {4.0, +0.0, +0.0}
    end

    test "validates object conditions and focus identity", %{caster: caster, spell: spell} do
      object = spawn_object(caster, 200, {2.0, +0.0, +0.0})
      condition = %Condition{entry: 900_047, type: :object_go_state, value1: 0}
      spell = %{spell | unit_targets: [], object_targets: [%ObjectTargets.Selector{entry: 200, condition: condition}]}
      assert %LocationTargets{error: :bad_targets} = SpellLocations.resolve(caster, spell, Target.none())
      Metadata.update(object, %{go_state: 0})
      assert SpellLocations.resolve(caster, spell, Target.none()).by_effect[0].guid == object
      spell = %{spell | object_targets: [%ObjectTargets.Selector{entry: 0}]}
      assert %LocationTargets{error: :bad_targets} = SpellLocations.resolve(caster, spell, Target.none())
      assert SpellLocations.resolve(caster, spell, Target.none(), %{guid: object}).by_effect[0].guid == object
    end

    test "rejects absent owners, other copies, hidden objects and out of range targets", context do
      %{caster: caster, spell: spell} = context
      other = %{caster | internal: %{caster.internal | world: WorldRef.instance(999, 702)}}
      spawn_mob(other, 100, {+0.0, +0.0, +0.0})
      spawn_object(other, 200, {+0.0, +0.0, +0.0})
      spawn_mob(caster, 100, {+0.0, +0.0, 30.0})
      spawn_object(caster, 200, {+0.0, +0.0, 30.0})
      missing = spawn_mob(caster, 100, {1.0, +0.0, +0.0})
      stop_supervised!(missing.object.guid)
      hidden = spawn_object(caster, 200, {2.0, +0.0, +0.0})
      Metadata.update(hidden, %{go_spawned?: false})
      spell = %{spell | object_targets: [%ObjectTargets.Selector{entry: 200}]}
      locations = SpellLocations.resolve(caster, spell, Target.none())
      assert LocationTargets.validate(spell, locations) == {:error, :bad_targets}
    end
  end

  describe "resolve_requirements/4" do
    test "reports a missing focus before a missing scripted destination", %{caster: caster, spell: spell} do
      spell = %{object_summon(spell) | required_focus_id: 1351}
      state = %State{character: caster, guid: caster.object.guid}
      assert {:error, rejected} = Spellcasting.cast_result(state, spell, <<0::16>>)
      assert rejected.character.unit.power1 == 100
      assert rejected.character.internal.casting == nil
      assert_received {:"$gen_cast", {:send_packet, %SmsgCastResult{reason: 0x5E}}}
    end

    test "delivers a primary location effect only to its creature", %{caster: caster, spell: spell} do
      mob = spawn_mob(caster, 100, {2.0, +0.0, +0.0})

      spell = %{
        spell
        | effects: [hd(spell.effects), %Effect{index: 1, type: :heal, base_points: 30, implicit_target_a: :caster}]
      }

      unrelated = spawn_mob(caster, 200, {1.0, +0.0, +0.0})
      completed = launch(caster, spell, Target.unit(unrelated.object.guid))

      refute Enum.any?(
               completed.internal.events,
               &match?(%Effects.DeliverSpell{target_guid: guid} when guid == unrelated.object.guid, &1)
             )

      assert completed.unit.health == 50
      assert completed.unit.power1 == 90
      delivery = Enum.find(completed.internal.events, &is_struct(&1, Effects.DeliverSpell))
      assert delivery.target_guid == mob.object.guid
      assert delivery.cast_context.effect_indices == [0]
      assert delivery.cast_context.destination_position == {2.0, +0.0, +0.0}
      {healed, _} = SpellEffect.receive(mob, delivery.cast_context, spell, 1_000)
      assert healed.unit.health == 30

      assert Enum.any?(
               completed.internal.events,
               &match?(%Effects.SpellGo{targets: %{destination_location: {2.0, +0.0, +0.0}}}, &1)
             )
    end

    test "summons at an object destination and projects the object hit", %{caster: caster, spell: spell} do
      object = spawn_object(caster, 200, {4.0, +0.0, +0.0})
      spell = object_summon(spell)
      completed = launch(caster, spell, Target.none())

      assert Enum.any?(
               completed.internal.events,
               &match?(%Effects.SummonGameObject{entry: 300, position: {4.0, +0.0, +0.0, +0.0}}, &1)
             )

      packet = Enum.find(completed.internal.events, &is_struct(&1, Effects.SpellGo))
      assert object in packet.hit_guids
      assert packet.targets.destination_location == {4.0, +0.0, +0.0}
      refute Enum.any?(completed.internal.events, &match?(%Effects.DeliverSpell{target_guid: ^object}, &1))
    end

    test "revalidates the location before power and cooldown costs", %{caster: caster, spell: spell} do
      mob = spawn_mob(caster, 100, {2.0, +0.0, +0.0})
      casting = caster |> Casting.start(spell, Target.none(), 1_000) |> Casting.complete(1_000)
      assert [%Effects.CheckCastRequirements{cast: cast}] = casting.internal.events
      stop_supervised!(mob.object.guid)
      failed = Casting.resolve_requirements(casting, cast, SpellRequirements.resolve(caster, spell), 1_000)
      assert failed.internal.casting == nil
      assert failed.unit.power1 == 100
      assert failed.internal.cooldowns == %{}
      refute Enum.any?(failed.internal.events, &is_struct(&1, Effects.SpellGo))
    end

    test "triggered casts retain the location and require the original caster", %{caster: caster, spell: spell} do
      object = spawn_object(caster, 200, {4.0, +0.0, +0.0})
      spell = object_summon(spell)
      caster = %{caster | internal: %{caster.internal | spellbook: %{spell.id => spell}}}

      trigger = %Effects.TriggerSpell{
        source_guid: caster.object.guid,
        source_level: 60,
        spell_id: spell.id,
        target_guid: caster.object.guid
      }

      events = EffectResolver.resolve(caster, trigger)
      delivery = Enum.find(events, &is_struct(&1, Effects.DeliverSpell))
      assert delivery.target_guid == caster.object.guid
      assert delivery.cast_context.destination_position == {4.0, +0.0, +0.0}
      assert delivery.cast_context.effect_indices == [0]
      {_, effects} = SpellEffect.receive(caster, delivery.cast_context, spell, 1_000)
      assert Enum.any?(effects, &match?(%Effects.SummonGameObject{position: {4.0, +0.0, +0.0, +0.0}}, &1))
      assert Enum.any?(events, &match?(%Effects.SpellGo{hit_guids: [_, ^object]}, &1))

      assert [%Effects.TriggerSpellRequest{source_guid: 123}] =
               EffectResolver.resolve(caster, %{trigger | source_guid: 123})
    end

    test "secondary locations preserve explicit unit targeting", %{caster: caster, spell: spell} do
      location = spawn_mob(caster, 100, {2.0, +0.0, +0.0})
      explicit = spawn_mob(caster, 200, {5.0, +0.0, +0.0})

      spell = %{
        spell
        | attributes: MapSet.new([:ignore_line_of_sight]),
          effects: [
            %{hd(spell.effects) | implicit_target_a: :any_unit, implicit_target_b: :script_location_near_caster}
          ]
      }

      targets = Target.unit(explicit.object.guid)
      requirements = SpellRequirements.resolve(caster, spell, targets)

      plan =
        SpellTargetResolver.resolve_plan(caster, spell, targets, requirements.units, locations: requirements.locations)

      assert UnitTargets.guids(plan) == [explicit.object.guid]
      refute location.object.guid in UnitTargets.guids(plan)
      hostile = %{spell | effects: [%{hd(spell.effects) | implicit_target_a: :target_enemy}]}
      assert {:error, :bad_implicit_targets} = CastValidation.validate_target(caster, hostile, Target.none(), nil)
    end

    test "corpse destinations summon at the body and retain corpse script delivery", %{caster: caster, spell: spell} do
      corpse = spawn_mob(caster, 100, {4.0, +0.0, +0.0}, health: 0)

      spell = %{
        spell
        | id: 12_699,
          attributes: MapSet.new([:allow_dead_target, :ignore_line_of_sight]),
          effects: [
            %Effect{
              index: 0,
              type: :summon_wild,
              misc_value: 8612,
              implicit_target_a: :target_enemy,
              implicit_target_b: :script_location_near_caster
            },
            %Effect{index: 1, type: :dummy, implicit_target_a: :target_enemy}
          ],
          unit_targets: [%Selector{entry: 100, alive?: false}]
      }

      completed = launch(caster, spell, Target.unit(corpse.object.guid))

      assert Enum.any?(
               completed.internal.events,
               &match?(%Effects.SummonWild{entry: 8612, position: {4.0, +0.0, +0.0, +0.0}}, &1)
             )

      delivery = Enum.find(completed.internal.events, &is_struct(&1, Effects.DeliverSpell))
      assert delivery.target_guid == corpse.object.guid
      {_, events} = SpellEffect.receive(corpse, delivery.cast_context, spell, 1_000)
      assert Enum.any?(events, &match?(%Effects.DespawnSelf{duration_ms: 1_000}, &1))
    end

    test "persistent areas do not deliver their effect to the location creature", %{caster: caster, spell: spell} do
      spawn_mob(caster, 100, {2.0, +0.0, +0.0})
      spell = %{spell | effects: [%{hd(spell.effects) | type: :persistent_area_aura}]}
      requirements = SpellRequirements.resolve(caster, spell)

      plan =
        SpellTargetResolver.resolve_plan(caster, spell, Target.none(), requirements.units,
          locations: requirements.locations
        )

      assert UnitTargets.guids(plan) == []
    end
  end

  defp caster(_context) do
    caster = %Character{
      object: %Object{guid: Guid.from_low_guid(:player, System.unique_integer([:positive]) + 84_000_000)},
      unit: %Unit{health: 20, max_health: 100, power1: 100, max_power1: 100, level: 60, combat_reach: +0.0},
      player: %Player{},
      movement_block: %MovementBlock{position: {+0.0, +0.0, +0.0, +0.0}},
      internal: %Internal{world: WorldRef.instance(999, 701)}
    }

    spell = %Spell{
      id: 900_946,
      range_yards: 10.0,
      mana_cost: 10,
      power_type: 0,
      effects: [%Effect{index: 0, type: :heal, base_points: 10, implicit_target_a: :script_location_near_caster}],
      unit_targets: [%Selector{entry: 100}]
    }

    %{caster: caster, spell: spell}
  end

  defp spawn_mob(caster, entry, {x, y, z}, opts \\ []) do
    guid = Guid.from_low_guid(:unit, entry, rem(System.unique_integer([:positive]), 1_000_000) + 8_000_000)

    mob = %Mob{
      object: %Object{guid: guid, entry: entry},
      unit: %Unit{
        health: Keyword.get(opts, :health, 20),
        max_health: 100,
        level: Keyword.get(opts, :level, 60),
        combat_reach: Keyword.get(opts, :combat_reach, +0.0)
      },
      movement_block: %MovementBlock{position: {x, y, z, +0.0}},
      internal: %Internal{world: caster.internal.world}
    }

    start_supervised!(%{
      id: guid,
      start:
        {Agent, :start_link,
         [
           fn ->
             Entity.register(guid)
             World.update_position(mob)

             Metadata.put(guid, %{
               entry: entry,
               alive?: mob.unit.health > 0,
               level: mob.unit.level,
               health: mob.unit.health,
               health_pct: mob.unit.health * 1.0,
               max_health: 100,
               combat_reach: mob.unit.combat_reach
             })

             mob
           end
         ]}
    })

    on_exit(fn ->
      World.remove_position(mob)
      Metadata.delete(guid)
    end)

    mob
  end

  defp spawn_object(caster, entry, {x, y, z}) do
    template = %GameObjectTemplate{entry: entry, type: 0, size: 1.0, flags: 0, display_id: 1, faction: 0}
    object = GameObject.build_summoned(template, caster.internal.world, {x, y, z, +0.0})
    start_supervised!({GameObjectServer, object}, id: object.object.guid)
    object.object.guid
  end

  defp object_summon(spell) do
    %{
      spell
      | effects: [%{hd(spell.effects) | type: :summon_object_wild, misc_value: 300}],
        unit_targets: [],
        object_targets: [%ObjectTargets.Selector{entry: 200}]
    }
  end

  defp launch(caster, spell, targets) do
    casting = caster |> Casting.start(spell, targets, 1_000) |> Casting.complete(1_000)
    assert [%Effects.CheckCastRequirements{cast: cast}] = casting.internal.events
    Casting.resolve_requirements(casting, cast, SpellRequirements.resolve(caster, spell, targets), 1_000)
  end
end
