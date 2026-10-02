defmodule ThistleTea.Game.World.Spell.SpellDatabaseLocationsTest do
  use ExUnit.Case, async: false

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
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.LocationTargets
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EffectResolver
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Spell.SpellLocations
  alias ThistleTea.Game.World.Spell.SpellRequirements
  alias ThistleTea.Test.Unique

  setup [:caster, :position]

  describe "resolve/4" do
    test "replaces supplied coordinates with the cached same-map destination", %{caster: caster, spell: spell} do
      targets = Target.at({100.0, 100.0, 100.0})
      locations = SpellLocations.resolve(caster, spell, targets)
      assert LocationTargets.validate(spell, locations) == :ok
      assert locations.by_effect[0].kind == :database
      assert locations.by_effect[0].guid == nil
      assert LocationTargets.apply(targets, locations).destination_location == {30.0, 40.0, 50.0}
    end

    test "leaves coordinates unchanged when the row is missing or belongs to another map", context do
      %{caster: caster, spell: spell} = context
      targets = Target.at({1.0, 2.0, 3.0})
      other_map = %{caster | internal: %{caster.internal | world: WorldRef.open(998)}}

      for actor <- [other_map, caster] do
        locations = SpellLocations.resolve(actor, spell, targets)
        assert locations.by_effect == %{}
        assert LocationTargets.validate(spell, locations) == :ok
        assert LocationTargets.apply(targets, locations) == targets
        :ets.delete(SpellLoader, {:target_position, spell.id})
      end
    end

    test "ordinary teleports retain their separate cross-map destination path", %{caster: caster, spell: spell} do
      spell = %{spell | effects: [%{hd(spell.effects) | type: :teleport_units}]}
      refute LocationTargets.required?(spell)
      assert SpellLocations.resolve(caster, spell, Target.none()).by_effect == %{}
    end
  end

  describe "resolve_requirements/4" do
    test "all summon families receive fixed coordinates in the current world", %{caster: caster, spell: spell} do
      for {type, event_type} <- [
            summon_wild: Effects.SummonWild,
            summon_guardian: Effects.SummonGuardians,
            summon_object_wild: Effects.SummonGameObject
          ] do
        spell = %{spell | effects: [%{hd(spell.effects) | type: type}]}
        completed = launch(caster, spell, Target.none())
        event = Enum.find(completed.internal.events, &is_struct(&1, event_type))
        assert event.position == {30.0, 40.0, 50.0, 0.0}
        assert completed.internal.world == caster.internal.world
        assert completed.unit.power1 == 90
        packet = Enum.find(completed.internal.events, &is_struct(&1, Effects.SpellGo))
        assert packet.targets.destination_location == {30.0, 40.0, 50.0}
      end
    end

    test "ground auras use the database location", %{caster: caster, spell: spell} do
      effect = %{hd(spell.effects) | type: :persistent_area_aura, aura: :periodic_damage, radius_yards: 5.0}
      spell = %{spell | duration_ms: 10_000, effects: [effect]}
      completed = launch(caster, spell, Target.none())
      event = Enum.find(completed.internal.events, &is_struct(&1, Effects.SpawnAreaEffect))
      assert event.position == {30.0, 40.0, 50.0}
      assert event.duration_ms == 10_000
      assert event.radius_yards == 5.0
    end

    test "destination area effects use nearby units in the current copy", %{caster: caster, spell: spell} do
      far = mob(caster, {0.0, 0.0, 0.0})
      near = mob(caster, {31.0, 40.0, 50.0})
      other = %{caster | internal: %{caster.internal | world: WorldRef.instance(999, 882)}}
      mob(other, {31.0, 40.0, 50.0})

      effect = %{
        hd(spell.effects)
        | type: :school_damage,
          base_points: 9,
          radius_yards: 5.0,
          implicit_target_b: :script_units_at_destination
      }

      spell = %{spell | school: :physical, attributes: MapSet.new([:ignore_line_of_sight]), effects: [effect]}
      completed = launch(caster, spell, Target.unit(far.object.guid))

      assert [%Effects.DeliverSpell{target_guid: guid, cast_context: context}] =
               Enum.filter(completed.internal.events, &is_struct(&1, Effects.DeliverSpell))

      assert guid == near.object.guid
      assert context.effect_indices == [0]
      assert context.destination_position == {30.0, 40.0, 50.0}
      {damaged, _events} = SpellEffect.receive(near, context, spell, 1_000)
      assert damaged.unit.health == 11
    end
  end

  describe "resolve/2" do
    test "triggered casts resolve fixed coordinates at the original caster", %{caster: caster, spell: spell} do
      caster = %{caster | internal: %{caster.internal | spellbook: %{spell.id => spell}}}

      trigger = %Effects.TriggerSpell{
        source_guid: caster.object.guid,
        source_level: 60,
        spell_id: spell.id,
        target_guid: caster.object.guid
      }

      events = EffectResolver.resolve(caster, trigger)
      delivery = Enum.find(events, &is_struct(&1, Effects.DeliverSpell))
      assert delivery.cast_context.destination_position == {30.0, 40.0, 50.0}
      assert delivery.cast_context.effect_indices == [0]
      {_, effects} = SpellEffect.receive(caster, delivery.cast_context, spell, 1_000)
      assert [%Effects.SummonWild{position: {30.0, 40.0, 50.0, +0.0}}] = effects

      assert [%Effects.TriggerSpellRequest{source_guid: 123}] =
               EffectResolver.resolve(caster, %{trigger | source_guid: 123})
    end

    test "teleports retain the configured facing", %{caster: caster, spell: spell} do
      assert [%Effects.TeleportToWorld{world: 999, position: {30.0, 40.0, 50.0}, orientation: 1.25}] =
               EffectResolver.resolve(caster, Effects.teleport_to_spell_target(spell.id))

      EventSink.emit(caster, Effects.teleport_to_spell_target(spell.id), Context.new(self()))
      assert_received {:"$gen_cast", {:start_teleport, 30.0, 40.0, 50.0, 1.25, 999}}
    end
  end

  defp caster(_context) do
    caster = %Character{
      object: %Object{guid: Unique.integer()},
      unit: %Unit{health: 100, max_health: 100, power1: 100, max_power1: 100, level: 60},
      player: %Player{},
      internal: %Internal{world: WorldRef.instance(999, 881)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    spell = %Spell{
      id: 900_017,
      mana_cost: 10,
      power_type: 0,
      effects: [%Effect{index: 0, type: :summon_wild, misc_value: 100, implicit_target_a: :database_location}]
    }

    %{caster: caster, spell: spell}
  end

  defp position(%{spell: spell}) do
    key = {:target_position, spell.id}
    previous = :ets.lookup(SpellLoader, key)
    :ets.insert(SpellLoader, {key, %{map: 999, x: 30.0, y: 40.0, z: 50.0, orientation: 1.25}})

    on_exit(fn ->
      :ets.delete(SpellLoader, key)
      :ets.insert(SpellLoader, previous)
    end)

    :ok
  end

  defp mob(caster, {x, y, z}) do
    guid = Guid.from_low_guid(:unit, 100, Unique.integer())

    mob = %Mob{
      object: %Object{guid: guid, entry: 100},
      unit: %Unit{health: 20, max_health: 100, level: 60, combat_reach: 0.0},
      internal: %Internal{world: caster.internal.world},
      movement_block: %MovementBlock{position: {x, y, z, 0.0}}
    }

    {:ok, _} = Entity.register(guid)
    World.update_position(mob)
    Metadata.put(guid, %{entry: 100, alive?: true, level: 60, combat_reach: 0.0})

    on_exit(fn ->
      World.remove_position(mob)
      Metadata.delete(guid)
    end)

    mob
  end

  defp launch(caster, spell, targets) do
    casting = caster |> Casting.start(spell, targets, 1_000) |> Casting.complete(1_000)
    assert [%Effects.CheckCastRequirements{cast: cast}] = casting.internal.events
    Casting.resolve_requirements(casting, cast, SpellRequirements.resolve(caster, spell, targets), 1_000)
  end
end
