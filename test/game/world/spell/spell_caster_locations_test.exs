defmodule ThistleTea.Game.World.Spell.SpellCasterLocationsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.LocationTargets
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.EffectResolver
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Entity.GameObject.SpellCast, as: ObjectSpellCast
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.Spell.SpellLocations
  alias ThistleTea.Game.World.Spell.SpellRequirements

  setup [:caster]

  describe "resolve/4" do
    test "keeps explicit destinations, including the origin", %{caster: caster, spell: spell} do
      for position <- [{0.0, 0.0, 0.0}, {50.0, 60.0, 70.0}] do
        targets = Target.at(position)
        locations = SpellLocations.resolve(caster, spell, targets)
        assert LocationTargets.validate(spell, locations) == :ok
        assert LocationTargets.apply(targets, locations).destination_location == position
      end
    end

    test "later compass selectors reuse the first destination", %{caster: caster, spell: spell} do
      second = %{hd(spell.effects) | index: 1, implicit_target_b: :caster_right}
      spell = %{spell | effects: spell.effects ++ [second]}
      locations = SpellLocations.resolve(caster, spell, Target.none())
      assert locations.by_effect[0].position == locations.by_effect[1].position
      {x, y, z} = locations.by_effect[0].position
      assert_in_delta x, 20.0, 0.00001
      assert_in_delta y, 20.0, 0.00001
      assert z == 40.0
    end

    test "an absent radius stays at the caster despite a long spell range", %{caster: caster, spell: spell} do
      spell = %{spell | range_yards: 100.0, effects: [%{hd(spell.effects) | radius_yards: nil}]}
      assert SpellLocations.resolve(caster, spell, Target.none()).by_effect[0].position == {20.0, 30.0, 40.0}
    end

    @tag :namigator_maps
    test "clips terrain obstructions on the caster's line", %{caster: caster, spell: spell} do
      caster = %{
        caster
        | internal: %{caster.internal | world: WorldRef.instance(0, 957)},
          movement_block: %{
            caster.movement_block
            | position: {-8949.95, -132.49, 83.53, :math.atan2(-31.51, 35.95) - :math.pi()}
          }
      }

      radius = :math.sqrt(35.95 * 35.95 + 31.51 * 31.51)
      spell = %{spell | effects: [%{hd(spell.effects) | radius_yards: radius}]}
      {x, y, z} = SpellLocations.resolve(caster, spell, Target.none()).by_effect[0].position
      assert Math.distance({x, y, z}, {-8914.0, -164.0, 82.0}) > 5.0
      assert Math.distance({x, y, z}, {-8949.95, -132.49, 83.53}) > 1.0
      assert Pathfinding.line_of_sight?(0, {-8949.95, -132.49, 83.53}, {x, y, z})
    end
  end

  describe "resolve_requirements/4" do
    test "directional leaps move only the caster and preserve the current copy and facing", data do
      %{caster: caster, spell: spell} = data
      completed = launch(caster, spell, Target.unit(2))
      refute Enum.any?(completed.internal.events, &is_struct(&1, Effects.DeliverSpell))
      teleport = Enum.find(completed.internal.events, &is_struct(&1, Effects.TeleportToWorld))
      assert teleport.world == caster.internal.world
      assert teleport.preserve_combat?
      assert completed.unit.power1 == 90
      {x, y, z} = teleport.position
      assert_in_delta x, 20.0, 0.00001
      assert_in_delta y, 20.0, 0.00001
      assert z == 40.0
      EventSink.emit(caster, teleport, Context.new(self()))
      assert_received {:"$gen_cast", {:combat_teleport, ^x, ^y, ^z, orientation, world}}
      assert orientation == :math.pi() / 2
      assert world == caster.internal.world
      packet = Enum.find(completed.internal.events, &is_struct(&1, Effects.SpellGo))
      assert packet.targets.destination_location == teleport.position
      assert packet.hit_guids == [caster.object.guid]
    end

    test "uses the pose at cast completion", %{caster: caster, spell: spell} do
      spell = %{spell | cast_time_ms: 2_000}
      casting = Casting.start(caster, spell, Target.none(), 1_000)
      moved = %{casting | movement_block: %{casting.movement_block | position: {50.0, 60.0, 70.0, 0.0}}}
      completed = Casting.complete(moved, 3_000)
      assert [%Effects.CheckCastRequirements{cast: cast}] = completed.internal.events
      requirements = SpellRequirements.resolve(moved, spell, cast.targets)
      completed = Casting.resolve_requirements(completed, cast, requirements, 3_000)
      teleport = Enum.find(completed.internal.events, &is_struct(&1, Effects.TeleportToWorld))
      {x, y, z} = teleport.position
      assert_in_delta x, 40.0, 0.00001
      assert_in_delta y, 60.0, 0.00001
      assert z == 70.0
    end

    test "owned summons consume the resolved location", %{caster: caster, spell: spell} do
      effect = %{hd(spell.effects) | type: :summon_game_object, misc_value: 2561, implicit_target_a: :caster_source}
      spell = %{spell | effects: [effect], duration_ms: 60_000}
      completed = launch(caster, spell, Target.at({0.0, 0.0, 0.0}))
      summon = Enum.find(completed.internal.events, &is_struct(&1, Effects.SummonGameObject))
      assert summon.position == {0.0, 0.0, 0.0, :math.pi() / 2}
      assert summon.duration_ms == 60_000
      assert summon.owned?
    end

    test "portals and lightwells pass their destination through object creation", %{caster: caster, spell: spell} do
      effect = %{hd(spell.effects) | type: :trans_door, misc_value: 181_621, implicit_target_a: :caster_source}
      spell = %{spell | effects: [effect], duration_ms: 60_000}
      completed = launch(caster, spell, Target.at({0.0, 0.0, 0.0}))
      summon = Enum.find(completed.internal.events, &is_struct(&1, Effects.SummonGameObject))
      assert summon.position == {0.0, 0.0, 0.0, :math.pi() / 2}
      assert summon.spell_id == spell.id
      assert summon.duration_ms == 60_000
    end

    test "summoning rituals retain the selected player when the client cast targets the caster", data do
      %{caster: caster, spell: spell} = data
      caster = %{caster | unit: %{caster.unit | target: 2}}
      effect = %{hd(spell.effects) | type: :trans_door, misc_value: 36_727, implicit_target_a: :caster_front}
      spell = %{spell | effects: [effect], duration_ms: 60_000}
      completed = launch(caster, spell, Target.unit(caster.object.guid))
      summon = Enum.find(completed.internal.events, &is_struct(&1, Effects.SummonGameObject))
      assert summon.target_guid == 2
      assert summon.entry == 36_727
    end
  end

  describe "receive/4" do
    test "possessed and demon summons retain resolved minion coordinates", %{caster: caster, spell: spell} do
      context = %{CastContext.from_caster(caster, spell, caster.object.guid) | destination_position: {0.0, 0.0, 0.0}}

      for type <- [:summon_demon, :summon_possessed] do
        effect = %Effect{type: type, misc_value: 4277, implicit_target_a: :minion_position, radius_yards: 10.0}

        {_, [%Effects.SummonCreature{summon: summon}]} =
          SpellEffect.receive(caster, context, %{spell | effects: [effect]}, 1_000)

        assert summon.position == {0.0, 0.0, 0.0, :math.pi() / 2}
      end
    end

    test "resolved leaps reject taxi passengers and foreign copies", %{caster: caster, spell: spell} do
      context = %{CastContext.from_caster(caster, spell, caster.object.guid) | destination_position: {1.0, 2.0, 3.0}}
      taxi = %{caster | internal: %{caster.internal | taxi_flight: %{}}}
      foreign = %{caster | internal: %{caster.internal | world: WorldRef.instance(999, 958)}}
      assert {^taxi, []} = SpellEffect.receive(taxi, context, spell, 1_000)
      assert {^foreign, []} = SpellEffect.receive(foreign, context, spell, 1_000)
    end
  end

  describe "resolve/2" do
    test "triggered spells resolve their original caster's pose", %{caster: caster, spell: spell} do
      caster = %{caster | internal: %{caster.internal | spellbook: %{spell.id => spell}}}

      trigger = %Effects.TriggerSpell{
        source_guid: caster.object.guid,
        source_level: 60,
        spell_id: spell.id,
        target_guid: 2
      }

      events = EffectResolver.resolve(caster, trigger)
      delivery = Enum.find(events, &is_struct(&1, Effects.DeliverSpell))
      assert delivery.target_guid == caster.object.guid

      assert delivery.cast_context.destination_position ==
               SpellLocations.resolve(caster, spell, Target.none()).by_effect[0].position
    end
  end

  describe "launch/4" do
    test "object origins supply destinations without a unit component", %{caster: caster, spell: spell} do
      object = %GameObject{object: caster.object, internal: caster.internal, movement_block: caster.movement_block}
      effect = %{hd(spell.effects) | type: :heal, implicit_target_a: :any_unit}
      launched = ObjectSpellCast.launch(object, %{spell | effects: [effect]}, 2)
      delivery = Enum.find(launched.internal.events, &is_struct(&1, Effects.DeliverSpell))
      assert delivery.target_guid == 2

      assert delivery.cast_context.destination_position ==
               SpellLocations.resolve(caster, spell, Target.none()).by_effect[0].position
    end
  end

  defp caster(_context) do
    caster = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, power1: 100, max_power1: 100, level: 60},
      player: %Player{},
      internal: %Internal{world: WorldRef.instance(999, 957)},
      movement_block: %MovementBlock{position: {20.0, 30.0, 40.0, :math.pi() / 2}}
    }

    spell = %Spell{
      id: 900_057,
      mana_cost: 10,
      power_type: 0,
      effects: [
        %Effect{index: 0, type: :leap, implicit_target_a: :caster, implicit_target_b: :caster_back, radius_yards: 10.0}
      ]
    }

    %{caster: caster, spell: spell}
  end

  defp launch(caster, spell, targets) do
    casting = caster |> Casting.start(spell, targets, 1_000) |> Casting.complete(1_000)
    assert [%Effects.CheckCastRequirements{cast: cast}] = casting.internal.events
    Casting.resolve_requirements(casting, cast, SpellRequirements.resolve(caster, spell, targets), 1_000)
  end
end
