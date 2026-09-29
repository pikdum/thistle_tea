defmodule ThistleTea.Game.World.Spell.SpellUnitsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.CastValidation
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.Spell.UnitTargets
  alias ThistleTea.Game.Core.Spell.UnitTargets.Selector
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EffectResolver
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Spell.SpellRequirements
  alias ThistleTea.Game.World.Spell.SpellUnits

  setup [:caster]

  describe "resolve/3" do
    test "prefers eligible selection and otherwise chooses nearest entry", %{caster: caster, spell: spell} do
      near = spawn_mob(caster, 100, {1.0, 0.0, 0.0})
      far = spawn_mob(caster, 100, {5.0, 0.0, 0.0})
      wrong = spawn_mob(caster, 200, {0.0, 0.0, 0.0})
      assert selected(caster, spell, Target.none()) == near.object.guid
      assert selected(caster, spell, Target.unit(far.object.guid)) == far.object.guid
      assert selected(caster, spell, Target.unit(wrong.object.guid)) == near.object.guid
    end

    test "rejects absent owners, other copies, height and removed corpses", %{caster: caster, spell: spell} do
      other = %{caster | internal: %{caster.internal | world: WorldRef.instance(999, 602)}}
      spawn_mob(other, 100, {0.0, 0.0, 0.0})
      spawn_mob(caster, 100, {0.0, 0.0, 20.0})
      missing = spawn_mob(caster, 100, {1.0, 0.0, 0.0})
      stop_supervised!(missing.object.guid)
      corpse = spawn_mob(caster, 100, {2.0, 0.0, 0.0}, health: 0)
      World.remove_position(corpse)
      spell = %{spell | unit_targets: [%Selector{entry: 100}, %Selector{entry: 100, alive?: false}]}
      assert %UnitTargets{error: :bad_targets} = SpellUnits.resolve(caster, spell, Target.none())
    end

    test "filters life states and inverse effect masks independently", %{caster: caster, spell: spell} do
      living = spawn_mob(caster, 100, {5.0, 0.0, 0.0})
      dead = spawn_mob(caster, 100, {1.0, 0.0, 0.0}, health: 0)

      spell = %{
        spell
        | effects: [hd(spell.effects), %{hd(spell.effects) | index: 1}],
          unit_targets: [
            %Selector{entry: 100, inverse_effect_mask: 2},
            %Selector{entry: 100, alive?: false, inverse_effect_mask: 1}
          ]
      }

      assert %UnitTargets{
               selected_guid: living.object.guid,
               by_effect: %{0 => [living.object.guid], 1 => [dead.object.guid]}
             } ==
               SpellUnits.resolve(caster, spell, Target.none())

      assert selected(caster, %{spell | effects: [hd(spell.effects)]}, Target.unit(dead.object.guid)) ==
               living.object.guid
    end

    test "checks cached conditions even on an explicit selection", %{caster: caster, spell: spell} do
      spawn_mob(caster, 100, {1.0, 0.0, 0.0}, level: 1)
      eligible = spawn_mob(caster, 100, {3.0, 0.0, 0.0}, level: 60)
      condition = %Condition{entry: 900_001, type: :level, value1: 60, value2: 0}
      spell = %{spell | unit_targets: [%Selector{entry: 100, condition: condition}]}
      assert selected(caster, spell, Target.none()) == eligible.object.guid
      impossible = %{condition | type: {:unsupported, 999}}
      spell = %{spell | unit_targets: [%Selector{entry: 100, condition: impossible}]}
      assert %UnitTargets{error: :bad_targets} = SpellUnits.resolve(caster, spell, Target.unit(eligible.object.guid))
    end

    test "applies health thresholds before preferring an explicit target", %{caster: caster, spell: spell} do
      healthy = spawn_mob(caster, 100, {1.0, 0.0, 0.0}, health: 20)
      wounded = spawn_mob(caster, 100, {3.0, 0.0, 0.0}, health: 5)
      condition = %Condition{entry: 16_053, type: :health_percent, value1: 10, value2: 2}
      spell = %{spell | unit_targets: [%Selector{entry: 100, condition: condition}]}
      assert selected(caster, spell, Target.unit(healthy.object.guid)) == wounded.object.guid
    end

    test "uses combat reach and effect radius", %{caster: caster, spell: spell} do
      mob = spawn_mob(caster, 100, {12.0, 0.0, 0.0}, combat_reach: 2.0)
      assert selected(caster, spell, Target.none()) == mob.object.guid
      spell = %{spell | effects: [%{hd(spell.effects) | radius_yards: 3.0}]}
      assert %UnitTargets{error: :bad_targets} = SpellUnits.resolve(caster, spell, Target.none())
    end
  end

  describe "area resolution" do
    test "source areas select every matching creature and exclude the caster", %{caster: caster, spell: spell} do
      first = spawn_mob(caster, 100, {1.0, 0.0, 0.0})
      second = spawn_mob(caster, 100, {2.0, 0.0, 0.0})
      spawn_mob(caster, 200, {0.0, 0.0, 0.0})
      spawn_mob(caster, 100, {0.0, 0.0, 20.0})
      spell = area_spell(spell, :script_units_at_source)
      units = SpellUnits.resolve(caster, spell, Target.self(caster.object.guid))
      assert units.by_effect == %{0 => [first.object.guid, second.object.guid]}
      assert units.selected_guid == nil
      assert UnitTargets.item_selection(Target.none(), units, 123) == Target.none()
    end

    test "respects source and destination locations independently", %{caster: caster, spell: spell} do
      source = spawn_mob(caster, 100, {30.0, 0.0, 0.0})
      destination = spawn_mob(caster, 100, {-30.0, 0.0, 0.0})
      spawn_mob(caster, 100, {1.0, 0.0, 0.0})
      spell = area_spell(spell, :script_units_at_source)

      spell = %{
        spell
        | effects: [hd(spell.effects), %{hd(spell.effects) | index: 1, implicit_target_a: :script_units_at_destination}]
      }

      targets = %{Target.none() | source_location: {30.0, 0.0, 0.0}, destination_location: {-30.0, 0.0, 0.0}}

      assert SpellUnits.resolve(caster, spell, targets).by_effect ==
               %{0 => [source.object.guid], 1 => [destination.object.guid]}
    end

    test "caster origin modes override supplied coordinates", %{caster: caster, spell: spell} do
      near = spawn_mob(caster, 100, {1.0, 0.0, 0.0})
      spawn_mob(caster, 100, {30.0, 0.0, 0.0})
      targets = %{Target.at({30.0, 0.0, 0.0}) | source_location: {30.0, 0.0, 0.0}}

      for {origin, mode} <- [
            {:caster_source, :script_units_at_source},
            {:caster_destination, :script_units_at_destination}
          ] do
        spell = area_spell(spell, mode)
        spell = %{spell | effects: [%{hd(spell.effects) | implicit_target_a: origin, implicit_target_b: mode}]}
        assert SpellUnits.resolve(caster, spell, targets).by_effect == %{0 => [near.object.guid]}
      end
    end

    test "unrestricted destination areas include their caster and permit empty areas", %{caster: caster, spell: spell} do
      mob = spawn_mob(caster, 200, {2.0, 0.0, 0.0})
      spell = %{area_spell(spell, :script_units_at_destination) | unit_targets: []}
      units = SpellUnits.resolve(caster, spell, Target.none())
      assert units.by_effect == %{0 => [caster.object.guid, mob.object.guid]}
      empty = SpellUnits.resolve(caster, spell, Target.at({100.0, 0.0, 0.0}))
      assert empty.by_effect == %{0 => []}
      assert UnitTargets.validate(spell, empty) == :ok
    end

    test "an excluded selector does not turn into an unrestricted area", %{caster: caster, spell: spell} do
      spawn_mob(caster, 100, {1.0, 0.0, 0.0})

      spell = %{
        area_spell(spell, :script_units_at_source)
        | unit_targets: [%Selector{entry: 100, inverse_effect_mask: 1}]
      }

      assert SpellUnits.resolve(caster, spell, Target.none()).by_effect == %{0 => []}
    end

    test "retains life state and target caps per effect", %{caster: caster, spell: spell} do
      first = spawn_mob(caster, 100, {1.0, 0.0, 0.0})
      selected = spawn_mob(caster, 100, {3.0, 0.0, 0.0})
      dead = spawn_mob(caster, 100, {2.0, 0.0, 0.0}, health: 0)
      spell = %{area_spell(spell, :script_units_at_source) | max_targets: 1}

      spell = %{
        spell
        | effects: [hd(spell.effects), %{hd(spell.effects) | index: 1}],
          unit_targets: [
            %Selector{entry: 100, inverse_effect_mask: 2},
            %Selector{entry: 100, alive?: false, inverse_effect_mask: 1}
          ]
      }

      units = SpellUnits.resolve(caster, spell, Target.unit(selected.object.guid))
      assert units.by_effect == %{0 => [selected.object.guid], 1 => [dead.object.guid]}
      refute first.object.guid in UnitTargets.guids(units)
    end

    test "uses a sixty-degree cone and wraps the caster's orientation", %{caster: caster, spell: spell} do
      front = spawn_mob(caster, 100, {5.0, 0.0, 0.0})
      edge = spawn_mob(caster, 100, {4.0, 2.0, 0.0})
      side = spawn_mob(caster, 100, {4.0, 3.0, 0.0})
      rear = spawn_mob(caster, 100, {-5.0, 0.0, 0.0})
      spell = area_spell(spell, :script_units_in_cone)
      units = SpellUnits.resolve(caster, spell, Target.unit(rear.object.guid))
      assert MapSet.new(UnitTargets.guids(units)) == MapSet.new([front.object.guid, edge.object.guid])
      refute side.object.guid in UnitTargets.guids(units)
      turned = %{caster | movement_block: %{caster.movement_block | position: {0.0, 0.0, 0.0, :math.pi()}}}
      assert UnitTargets.guids(SpellUnits.resolve(turned, spell, Target.none())) == [rear.object.guid]
      wrapped = %{caster | movement_block: %{caster.movement_block | position: {0.0, 0.0, 0.0, 2 * :math.pi()}}}
      assert UnitTargets.guids(SpellUnits.resolve(wrapped, spell, Target.none())) == UnitTargets.guids(units)
    end

    test "destination summon and ground effects do not execute on nearby units", %{caster: caster, spell: spell} do
      spawn_mob(caster, 100, {1.0, 0.0, 0.0})

      for type <- [:summon, :summon_wild, :summon_object_wild, :persistent_area_aura] do
        spell = area_spell(spell, :script_units_at_destination)
        spell = %{spell | effects: [%{hd(spell.effects) | type: type}]}
        assert SpellUnits.resolve(caster, spell, Target.none()).by_effect == %{0 => []}
      end
    end

    test "mixed areas deliver each heal only to its own recipients", %{caster: caster, spell: spell} do
      first = spawn_mob(caster, 100, {1.0, 0.0, 0.0})
      second = spawn_mob(caster, 100, {2.0, 0.0, 0.0})
      other = spawn_mob(caster, 200, {3.0, 0.0, 0.0})
      spell = mixed_spell(spell)

      effects =
        Enum.map(spell.effects, fn effect ->
          if effect.index < 2, do: %{effect | implicit_target_a: :script_units_at_source}, else: effect
        end)

      spell = %{spell | effects: effects, attributes: MapSet.new([:ignore_line_of_sight])}
      completed = launch(caster, spell)
      assert completed.unit.health == 50
      deliveries = Enum.filter(completed.internal.events, &is_struct(&1, Effects.DeliverSpell))
      assert_delivery(deliveries, first, 0, 30)
      assert_delivery(deliveries, second, 0, 30)
      assert_delivery(deliveries, other, 1, 40)
    end
  end

  describe "launch and delivery" do
    test "rechecks vanished targets before costs", %{caster: caster, spell: spell} do
      mob = spawn_mob(caster, 100, {1.0, 0.0, 0.0})
      casting = caster |> Casting.start(spell, Target.none(), 1_000) |> Casting.complete(1_000)
      assert [%Effects.CheckCastRequirements{cast: cast}] = casting.internal.events
      stop_supervised!(mob.object.guid)
      failed = Casting.resolve_requirements(casting, cast, SpellRequirements.resolve(caster, spell), 1_000)
      assert failed.internal.casting == nil
      assert failed.unit.power1 == 100
      assert failed.internal.cooldowns == %{}
      refute Enum.any?(failed.internal.events, &match?(%Effects.SpellGo{}, &1))
    end

    test "keeps each creature effect separate from the caster's heal", %{caster: caster, spell: spell} do
      first = spawn_mob(caster, 100, {1.0, 0.0, 0.0})
      second = spawn_mob(caster, 200, {2.0, 0.0, 0.0})
      spell = mixed_spell(spell)
      completed = launch(caster, spell)
      assert completed.unit.health == 50
      assert completed.unit.power1 == 90
      assert completed.internal.casting == nil
      deliveries = Enum.filter(completed.internal.events, &is_struct(&1, Effects.DeliverSpell))
      assert length(deliveries) == 2
      assert_delivery(deliveries, first, 0, 30)
      assert_delivery(deliveries, second, 1, 40)
      assert %Effects.SpellGo{hit_guids: hits} = Enum.find(completed.internal.events, &is_struct(&1, Effects.SpellGo))
      assert MapSet.new(hits) == MapSet.new([first.object.guid, second.object.guid, caster.object.guid])
    end

    test "triggered casts preserve per-effect recipients and require the caster owner", %{caster: caster, spell: spell} do
      first = spawn_mob(caster, 100, {1.0, 0.0, 0.0})
      second = spawn_mob(caster, 200, {2.0, 0.0, 0.0})
      spell = mixed_spell(spell)
      caster = %{caster | internal: %{caster.internal | spellbook: %{spell.id => spell}}}

      trigger = %Effects.TriggerSpell{
        source_guid: caster.object.guid,
        source_level: 60,
        spell_id: spell.id,
        target_guid: caster.object.guid
      }

      deliveries = caster |> EffectResolver.resolve(trigger) |> Enum.filter(&is_struct(&1, Effects.DeliverSpell))
      assert_delivery(deliveries, first, 0, 30)
      assert_delivery(deliveries, second, 1, 40)
      assert_delivery(deliveries, caster, 2, 50)
      assert [%Effects.TriggerSpellRequest{}] = EffectResolver.resolve(caster, %{trigger | source_guid: 123})
      stop_supervised!(first.object.guid)
      assert [%Effects.SpellCastFailed{}] = EffectResolver.resolve(caster, trigger)
    end

    test "item casts report the resolved creature as their selected target", %{caster: caster, spell: spell} do
      mob = spawn_mob(caster, 100, {1.0, 0.0, 0.0})
      casting = caster |> Casting.start(spell, Target.self(caster.object.guid), 1_000, 123) |> Casting.complete(1_000)
      assert [%Effects.CheckCastRequirements{cast: cast}] = casting.internal.events
      completed = Casting.resolve_requirements(casting, cast, SpellRequirements.resolve(caster, spell), 1_000)
      launch = Enum.find(completed.internal.events, &is_struct(&1, Effects.SpellGo))
      assert Target.unit_guid(launch.targets) == mob.object.guid
      delivery = Enum.find(completed.internal.events, &is_struct(&1, Effects.DeliverSpell))
      assert delivery.cast_context.selected_target_guid == mob.object.guid
    end

    test "entry-bound corpse effects execute without a global dead-target flag", %{caster: caster, spell: spell} do
      corpse = spawn_mob(caster, 100, {1.0, 0.0, 0.0}, health: 0)

      spell = %{
        spell
        | effects: [%{hd(spell.effects) | type: :dummy}],
          unit_targets: [%Selector{entry: 100, alive?: false}],
          script_steps: [%ScriptStep{command: :cast_spell, datalong: 90_123, delay_ms: 0}]
      }

      context = %{CastContext.from_caster(caster, spell, corpse.object.guid) | target_role: :other, effect_indices: [0]}
      {dead, events} = SpellEffect.receive(corpse, context, spell, 1_000)
      assert dead.unit.health == 0
      assert Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 90_123}, &1))

      {_, events} =
        SpellEffect.receive(corpse, context, %{spell | unit_targets: [%Selector{entry: 200, alive?: false}]}, 1_000)

      refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
    end

    test "database script effects use the caster's existing script runner", %{caster: caster, spell: spell} do
      mob = spawn_mob(caster, 100, {1.0, 0.0, 0.0})
      steps = [%ScriptStep{command: :create_item, datalong: 9284, datalong2: 1, delay_ms: 0}]
      spell = %{spell | effects: [%{hd(spell.effects) | type: :script_effect}], script_steps: steps}
      context = %{CastContext.from_caster(caster, spell, mob.object.guid) | target_role: :other}
      {_, events} = SpellEffect.receive(mob, context, spell, 1_000)
      assert [%Effects.ForwardScriptSteps{target_guid: owner, source_guid: recipient, steps: ^steps}] = events
      assert owner == caster.object.guid
      assert recipient == mob.object.guid

      context = %{context | target_role: :caster, target_guid: caster.object.guid}
      {_, events} = SpellEffect.receive(caster, context, spell, 1_000)
      assert [%Effects.ScriptSteps{target_guid: ^owner, steps: ^steps}] = events
    end

    test "does not validate unrelated selection for scripted-only effects", %{caster: caster, spell: spell} do
      info = %{alive?: false, visible?: false, position: {WorldRef.instance(999, 602), 1_000.0, 0.0, 0.0}}
      assert :ok = CastValidation.validate_target(caster, spell, Target.unit(123), info)
      spell = %{spell | effects: spell.effects ++ [%Effect{index: 1, type: :heal, implicit_target_a: :target_ally}]}
      assert {:error, :bad_targets} = CastValidation.validate_target(caster, spell, Target.unit(123), info)
    end
  end

  defp caster(_context) do
    caster = %Character{
      object: %Object{guid: Guid.from_low_guid(:player, System.unique_integer([:positive]) + 83_000_000)},
      unit: %Unit{health: 20, max_health: 100, power1: 100, max_power1: 100, level: 60, combat_reach: 0.0},
      player: %Player{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.instance(999, 601)}
    }

    spell = %Spell{
      id: 900_900,
      range_yards: 10.0,
      mana_cost: 10,
      power_type: 0,
      effects: [%Effect{index: 0, type: :heal, base_points: 10, implicit_target_a: :creature_near_caster}],
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
        combat_reach: Keyword.get(opts, :combat_reach, 0.0)
      },
      movement_block: %MovementBlock{position: {x, y, z, 0.0}},
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

  defp selected(caster, spell, targets) do
    %UnitTargets{error: nil, by_effect: %{0 => [guid]}} = SpellUnits.resolve(caster, spell, targets)
    guid
  end

  defp area_spell(spell, mode) do
    %{
      spell
      | attributes: MapSet.new([:ignore_line_of_sight]),
        effects: [%{hd(spell.effects) | implicit_target_a: mode}]
    }
  end

  defp mixed_spell(spell) do
    %{
      spell
      | effects: [
          hd(spell.effects),
          %{hd(spell.effects) | index: 1, base_points: 20},
          %Effect{index: 2, type: :heal, base_points: 30, implicit_target_a: :caster}
        ],
        unit_targets: [%Selector{entry: 100, inverse_effect_mask: 2}, %Selector{entry: 200, inverse_effect_mask: 1}]
    }
  end

  defp launch(caster, spell) do
    casting = caster |> Casting.start(spell, Target.none(), 1_000) |> Casting.complete(1_000)
    assert [%Effects.CheckCastRequirements{cast: cast}] = casting.internal.events
    Casting.resolve_requirements(casting, cast, SpellRequirements.resolve(caster, spell), 1_000)
  end

  defp assert_delivery(deliveries, target, index, health) do
    delivery = Enum.find(deliveries, &(&1.target_guid == target.object.guid))
    assert delivery.cast_context.effect_indices == [index]
    {healed, _events} = SpellEffect.receive(target, delivery.cast_context, delivery.spell, 1_000)
    assert healed.unit.health == health
  end
end
