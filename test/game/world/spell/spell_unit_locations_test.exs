defmodule ThistleTea.Game.World.Spell.SpellUnitLocationsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.LocationTargets
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message.SmsgSpellGo
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EffectResolver
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Entity.GameObject.SpellCast, as: ObjectSpellCast
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Spell.SpellLocations
  alias ThistleTea.Game.World.Spell.SpellRequirements
  alias ThistleTea.Game.World.Spell.SpellTargetResolver
  alias ThistleTea.Test.FactionFixtures

  setup [{FactionFixtures, :seed}, :caster]

  describe "resolve/4" do
    test "replaces supplied coordinates with the selected unit's live position", %{caster: caster, spell: spell} do
      target = mob(caster, {20.0, 30.0, 1.0})
      targets = %{Target.unit(target.object.guid) | destination_location: {100.0, 100.0, 100.0}}
      locations = SpellLocations.resolve(caster, spell, targets)
      assert LocationTargets.validate(spell, locations) == :ok
      assert LocationTargets.apply(targets, locations).destination_location == {20.0, 30.0, 1.0}
      assert locations.by_effect[0].guid == target.object.guid

      moved = %{target | movement_block: %{target.movement_block | position: {25.0, 30.0, 2.0, 0.0}}}
      World.update_position(moved)
      assert SpellLocations.resolve(caster, spell, targets).by_effect[0].position == {25.0, 30.0, 2.0}
    end

    test "rejects absent owners, other copies, dead units and friendly enemies", %{caster: caster, spell: spell} do
      assert SpellLocations.resolve(caster, spell, Target.none()).error == :bad_targets
      assert SpellLocations.resolve(caster, spell, Target.self(caster.object.guid)).error == :bad_targets

      missing = mob(caster, {10.0, 0.0, 0.0})
      stop_supervised!(missing.object.guid)
      assert SpellLocations.resolve(caster, spell, Target.unit(missing.object.guid)).error == :bad_targets

      other = %{caster | internal: %{caster.internal | world: WorldRef.instance(999, 954)}}
      foreign = mob(other, {10.0, 0.0, 0.0})
      assert SpellLocations.resolve(caster, spell, Target.unit(foreign.object.guid)).error == :bad_targets

      dead = mob(caster, {10.0, 0.0, 0.0})
      Metadata.update(dead.object.guid, %{alive?: false})
      assert SpellLocations.resolve(caster, spell, Target.unit(dead.object.guid)).error == :targets_dead

      friendly = mob(caster, {10.0, 0.0, 0.0}, faction: friendly())
      assert SpellLocations.resolve(caster, spell, Target.unit(friendly.object.guid)).error == :target_friendly
    end

    test "keeps range and targetability checks at launch", %{caster: caster, spell: spell} do
      target = mob(caster, {60.0, 0.0, 0.0})
      assert SpellLocations.resolve(caster, spell, Target.unit(target.object.guid)).error == :out_of_range
      blocked = mob(caster, {10.0, 0.0, 0.0})
      Metadata.update(blocked.object.guid, %{unit_flags: 0x02000000})
      assert SpellLocations.resolve(caster, spell, Target.unit(blocked.object.guid)).error == :bad_targets
    end

    test "retains the void-zone height adjustment", %{caster: caster, spell: spell} do
      target = mob(caster, {10.0, 20.0, 30.0})
      location = SpellLocations.resolve(caster, %{spell | id: 28_863}, Target.unit(target.object.guid))
      assert location.by_effect[0].position == {10.0, 20.0, 30.3}
    end
  end

  describe "resolve_requirements/4" do
    test "summons at the unit without treating its position selector as an area", %{caster: caster, spell: spell} do
      target = mob(caster, {20.0, 0.0, 0.0})
      mob(caster, {21.0, 0.0, 0.0})
      spell = %{spell | effects: [%{hd(spell.effects) | type: :summon_wild, misc_value: 123}]}
      completed = launch(caster, spell, Target.unit(target.object.guid))
      summon = Enum.find(completed.internal.events, &is_struct(&1, Effects.SummonWild))
      assert summon.position == {20.0, 0.0, 0.0, 1.0}
      assert completed.unit.power1 == 90

      assert [%Effects.DeliverSpell{target_guid: guid}] = deliveries(completed)
      assert guid == target.object.guid
      refute Spell.area_of_effect?(spell)
    end

    test "splash effects hit the primary and nearby enemies exactly once in the current copy", context do
      %{caster: caster, spell: spell} = context
      primary = mob(caster, {20.0, 0.0, 0.0})
      nearby = mob(caster, {22.0, 0.0, 0.0})
      mob(caster, {2.0, 0.0, 0.0})
      mob(caster, {30.0, 0.0, 0.0})
      mob(caster, {21.0, 0.0, 0.0}, faction: friendly())
      other = %{caster | internal: %{caster.internal | world: WorldRef.instance(999, 954)}}
      mob(other, {20.0, 0.0, 0.0})
      effect = %{hd(spell.effects) | implicit_target_b: :aoe_enemy_at_dest, area_target?: true}
      spell = %{spell | effects: [effect]}
      completed = launch(caster, spell, Target.unit(primary.object.guid))
      hits = deliveries(completed)
      assert Enum.sort(Enum.map(hits, & &1.target_guid)) == Enum.sort([primary.object.guid, nearby.object.guid])
      assert Enum.all?(hits, &(&1.cast_context.destination_position == {20.0, 0.0, 0.0}))

      for target <- [primary, nearby] do
        hit = Enum.find(hits, &(&1.target_guid == target.object.guid))
        {damaged, _} = SpellEffect.receive(target, hit.cast_context, spell, 1_000)
        assert damaged.unit.health == 90
      end
    end

    test "rejects a vanished target before spending launch costs", %{caster: caster, spell: spell} do
      target = mob(caster, {20.0, 0.0, 0.0})
      targets = Target.unit(target.object.guid)
      casting = caster |> Casting.start(spell, targets, 1_000) |> Casting.complete(1_000)
      assert [%Effects.CheckCastRequirements{cast: cast}] = casting.internal.events
      stop_supervised!(target.object.guid)
      failed = Casting.resolve_requirements(casting, cast, SpellRequirements.resolve(caster, spell, targets), 1_000)
      assert failed.unit.power1 == 100
      assert failed.internal.casting == nil
      assert failed.internal.cooldowns == %{}
      refute Enum.any?(failed.internal.events, &is_struct(&1, Effects.SpellGo))
    end

    test "unit-location teleports move the caster rather than the selected unit", %{caster: caster, spell: spell} do
      target = mob(caster, {20.0, 0.0, 0.0})

      spell = %{
        spell
        | effects: [
            %Effect{index: 0, type: :teleport_units, implicit_target_a: :caster, implicit_target_b: :unit_location}
          ]
      }

      targets = Target.unit(target.object.guid)
      completed = launch(caster, spell, targets)
      assert deliveries(completed) == []
      teleport = Enum.find(completed.internal.events, &is_struct(&1, Effects.TeleportToWorld))
      assert teleport.world == caster.internal.world
      assert teleport.position == {20.0, 0.0, 0.0}
      assert teleport.preserve_combat?
      EventSink.emit(caster, teleport, Context.new(self()))
      world = caster.internal.world
      assert_received {:"$gen_cast", {:combat_teleport, 20.0, +0.0, +0.0, 1.0, ^world}}
    end
  end

  describe "resolve/2" do
    test "triggered summons retain the original caster and selected-unit destination", %{caster: caster, spell: spell} do
      target = mob(caster, {20.0, 0.0, 0.0})
      spell = %{spell | effects: [%{hd(spell.effects) | type: :summon_wild, misc_value: 123}]}
      caster = %{caster | internal: %{caster.internal | spellbook: %{spell.id => spell}}}

      trigger = %Effects.TriggerSpell{
        source_guid: caster.object.guid,
        source_level: 60,
        spell_id: spell.id,
        target_guid: target.object.guid
      }

      events = EffectResolver.resolve(caster, trigger)

      delivery =
        Enum.find(events, &match?(%Effects.DeliverSpell{target_guid: guid} when guid == caster.object.guid, &1))

      assert delivery.cast_context.destination_position == {20.0, 0.0, 0.0}
      assert delivery.cast_context.selected_target_guid == target.object.guid

      assert [%Effects.TriggerSpellRequest{source_guid: 123}] =
               EffectResolver.resolve(caster, %{trigger | source_guid: 123})
    end
  end

  describe "launch/4" do
    test "object casters resolve the selected location without a unit component", %{caster: caster, spell: spell} do
      target = mob(caster, {20.0, 0.0, 0.0})
      guid = Guid.runtime(:game_object, 100)

      object = %GameObject{
        object: %Object{guid: guid},
        internal: caster.internal,
        movement_block: caster.movement_block
      }

      Metadata.put(guid, %{faction_template: friendly()})
      on_exit(fn -> Metadata.delete(guid) end)
      launched = ObjectSpellCast.launch(object, spell, target.object.guid)
      assert [%Effects.DeliverSpell{target_guid: selected, cast_context: context}] = deliveries(launched)
      assert selected == target.object.guid
      assert context.caster_guid == guid
      assert context.destination_position == {20.0, 0.0, 0.0}
      assert context.effect_indices == [0]
    end
  end

  describe "for_packet/2" do
    test "preserves fireball visuals without losing its internal splash location", %{caster: caster, spell: spell} do
      target = mob(caster, {20.0, 0.0, 0.0})
      effect = %{hd(spell.effects) | implicit_target_b: :aoe_enemy_at_dest}
      spell = %{spell | id: 18_392, effects: [effect]}
      requirements = SpellRequirements.resolve(caster, spell, Target.unit(target.object.guid))
      targets = LocationTargets.apply(Target.unit(target.object.guid), requirements.locations)

      plan =
        SpellTargetResolver.resolve_plan(caster, spell, targets, requirements.units, locations: requirements.locations)

      assert plan.by_effect[0] == [target.object.guid]
      assert targets.destination_location == {20.0, 0.0, 0.0}

      EventSink.emit(caster, Effects.spell_go(caster.object.guid, spell.id, [target.object.guid], targets))
      assert_received {:"$gen_cast", {:send_packet, %SmsgSpellGo{targets: projected}}}
      assert projected == Target.unit(target.object.guid)
      assert LocationTargets.for_packet(26_789, targets) == targets
    end
  end

  defp caster(_context) do
    caster = %Character{
      object: %Object{guid: Guid.from_low_guid(:player, System.unique_integer([:positive]) + 89_000_000)},
      unit: %Unit{health: 100, max_health: 100, power1: 100, max_power1: 100, level: 60, faction_template: 1},
      player: %Player{},
      internal: %Internal{world: WorldRef.instance(999, 953)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 1.0}}
    }

    Entity.register(caster.object.guid)
    World.update_position(caster)
    Metadata.put(caster.object.guid, %{alive?: true, faction_template: friendly(), unit_flags: 0})

    on_exit(fn ->
      World.remove_position(caster)
      Metadata.delete(caster.object.guid)
    end)

    spell = %Spell{
      id: 900_053,
      range_yards: 40.0,
      mana_cost: 10,
      power_type: 0,
      school: :physical,
      attributes: MapSet.new([:ignore_line_of_sight]),
      effects: [
        %Effect{index: 0, type: :school_damage, base_points: 10, radius_yards: 5.0, implicit_target_a: :enemy_location}
      ]
    }

    %{caster: caster, spell: spell}
  end

  defp mob(caster, {x, y, z}, opts \\ []) do
    guid = Guid.from_low_guid(:unit, 100, rem(System.unique_integer([:positive]), 1_000_000) + 8_000_000)

    mob = %Mob{
      object: %Object{guid: guid, entry: 100},
      unit: %Unit{health: 100, max_health: 100, level: 60, combat_reach: 0.0},
      internal: %Internal{world: caster.internal.world},
      movement_block: %MovementBlock{position: {x, y, z, 0.0}}
    }

    metadata = %{
      alive?: true,
      level: 60,
      combat_reach: 0.0,
      faction_template: Keyword.get(opts, :faction, enemy()),
      faction_can_have_reputation?: false,
      unit_flags: 0
    }

    start_supervised!(%{
      id: guid,
      start:
        {Agent, :start_link,
         [
           fn ->
             Entity.register(guid)
             World.update_position(mob)
             Metadata.put(guid, metadata)
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

  defp friendly, do: %FactionTemplate{id: 1, faction: 1, faction_group: 3, friend_group: 2, enemy_group: 12}
  defp enemy, do: %FactionTemplate{id: 17, faction: 15, faction_group: 8, friend_group: 0, enemy_group: 1}

  defp deliveries(caster), do: Enum.filter(caster.internal.events, &is_struct(&1, Effects.DeliverSpell))

  defp launch(caster, spell, targets) do
    casting = caster |> Casting.start(spell, targets, 1_000) |> Casting.complete(1_000)
    assert [%Effects.CheckCastRequirements{cast: cast}] = casting.internal.events
    Casting.resolve_requirements(casting, cast, SpellRequirements.resolve(caster, spell, targets), 1_000)
  end
end
