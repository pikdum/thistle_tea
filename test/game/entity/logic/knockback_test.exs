defmodule ThistleTea.Game.Entity.Logic.KnockbackTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Falling
  alias ThistleTea.Game.Entity.Logic.Knockback
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:character]

  describe "apply/5" do
    test "launches away from the caster without teleporting the target", %{character: character} do
      context = %CastContext{caster_guid: 2, caster_position: {WorldRef.open(0), 0.0, -10.0, 0.0}}
      {updated, [event]} = Knockback.apply(character, context, 12.0, 7.0, 100)
      assert %Effects.Knockback{horizontal_speed: 12.0, vertical_speed: 7.0} = event
      assert_in_delta event.cos_angle, 0.0, 0.00001
      assert_in_delta event.sin_angle, 1.0, 0.00001
      assert updated.movement_block == character.movement_block
      assert updated.internal.fall == nil
    end

    test "self launches travel backward relative to facing", %{character: character} do
      {_, [event]} = Knockback.apply(character, %CastContext{caster_guid: 1}, 10.0, 10.0, 100)
      assert_in_delta event.cos_angle, -1.0, 0.00001
      assert_in_delta event.sin_angle, 0.0, 0.00001
    end

    test "does not interrupt the spell currently delivering its own launch", %{character: character} do
      cast = %{Cast.new(%Spell{id: 10_689}, Target.self(1), 0) | phase: :impact}
      character = put_in(character.internal.casting, cast)
      {updated, [_]} = Knockback.apply(character, %CastContext{caster_guid: 1}, 10.0, 10.0, 100)
      assert updated.internal.casting == cast
      assert updated.internal.events == []
    end

    test "root, stun, death, taxi and server movement suppress launch", %{character: character} do
      blocked = [
        put_in(character.unit.auras, [holder(10, :mod_root)]),
        put_in(character.unit.auras, [holder(11, :mod_stun)]),
        put_in(character.unit.health, 0),
        put_in(character.internal.taxi_flight, %{}),
        put_in(character.internal.movement_start_time, 1)
      ]

      for entity <- blocked do
        assert {^entity, []} = Knockback.apply(entity, %CastContext{caster_guid: 1}, 10.0, 10.0, 100)
      end

      context = %CastContext{caster_guid: 2, caster_position: {WorldRef.open(1), 1.0, 2.0, 3.0}}
      assert {^character, []} = Knockback.apply(character, context, 10.0, 10.0, 100)
    end

    test "supports possessed units and leaves ordinary creature movement to the server", %{character: character} do
      mob = struct!(Mob, Map.take(Map.from_struct(character), [:object, :unit, :internal, :movement_block]))
      assert {^mob, []} = Knockback.apply(mob, %CastContext{caster_guid: 1}, 10.0, 10.0, 100)
      cast = Cast.new(%Spell{id: 133, cast_time_ms: 3_000}, Target.unit(2), 0)

      {interrupted, []} =
        Knockback.apply(put_in(mob.internal.casting, cast), %CastContext{caster_guid: 1}, 10.0, 10.0, 100)

      assert interrupted.internal.casting == nil
      possessed = put_in(mob.internal.pet, %Pet{owner_guid: 2, possessed?: true})
      assert {_, [%Effects.Knockback{}]} = Knockback.apply(possessed, %CastContext{caster_guid: 1}, 10.0, 10.0, 100)
    end

    test "interrupts a cast and resets an earlier fall", %{character: character} do
      cast = Cast.new(%Spell{id: 133, cast_time_ms: 3_000}, Target.unit(2), 0)

      character = %{
        character
        | internal: %{character.internal | casting: cast, fall: %Falling{height: 100.0, far?: true}}
      }

      {updated, [_]} = Knockback.apply(character, %CastContext{caster_guid: 1}, 10.0, 10.0, 100)
      assert updated.internal.casting == nil
      assert updated.internal.fall == nil
      assert [%Effects.SpellCastFailed{spell_id: 133, reason: :interrupted}] = updated.internal.events
    end

    test "removes Dream Fog before checking the remaining controls", %{character: character} do
      character = put_in(character.unit.auras, [holder(24_778, :mod_stun)])
      {updated, events} = Knockback.apply(character, %CastContext{caster_guid: 1}, 10.0, 10.0, 100)
      assert updated.unit.auras == []
      assert Enum.any?(events, &is_struct(&1, Effects.Knockback))
    end
  end

  describe "pull/4" do
    test "lands at the caster boundary across height differences", %{character: character} do
      character = put_in(character.unit.bounding_radius, 0.5)

      for height <- [-20.0, 0.0, 20.0] do
        context = %CastContext{
          caster_guid: 2,
          caster_bounding_radius: 0.5,
          caster_position: {WorldRef.open(0), 24.0, 32.0, height}
        }

        {updated, [event]} = Knockback.pull(character, context, 30.0, 100)
        assert %Effects.Knockback{horizontal_speed: 30.0} = event
        assert_in_delta event.cos_angle, 0.6, 0.00001
        assert_in_delta event.sin_angle, 0.8, 0.00001
        flight_time = 39.0 / event.horizontal_speed
        landing_height = event.vertical_speed * flight_time - 19.29110527038574 * flight_time * flight_time / 2
        assert_in_delta landing_height, height, 0.00001
        assert updated.movement_block == character.movement_block
      end
    end

    test "ignores overlapping targets, self, other worlds and invalid speeds", %{character: character} do
      context = %CastContext{caster_guid: 2, caster_position: {WorldRef.open(0), 10.0, 0.0, 0.0}}

      for invalid <- [
            %{context | caster_guid: 1},
            %{context | caster_position: nil},
            %{context | caster_position: {WorldRef.open(1), 10.0, 0.0, 0.0}},
            %{context | caster_position: {WorldRef.open(0), 0.1, 0.0, 20.0}}
          ] do
        assert {^character, []} = Knockback.pull(character, invalid, 30.0, 100)
      end

      for speed <- [0.0, -1.0, nil] do
        assert {^character, []} = Knockback.pull(character, context, speed, 100)
      end
    end

    test "shares cast interruption and movement restrictions without removing Dream Fog", %{character: character} do
      context = %CastContext{caster_guid: 2, caster_position: {WorldRef.open(0), 30.0, 0.0, 0.0}}
      cast = Cast.new(%Spell{id: 133, cast_time_ms: 3_000}, Target.unit(2), 0)
      casting = put_in(character.internal.casting, cast)
      {updated, [%Effects.Knockback{}]} = Knockback.pull(casting, context, 30.0, 100)
      assert updated.internal.casting == nil
      assert [%Effects.SpellCastFailed{reason: :interrupted}] = updated.internal.events

      for blocked <- [
            put_in(casting.unit.auras, [holder(24_778, :mod_stun)]),
            put_in(casting.unit.auras, [holder(10, :mod_root)]),
            put_in(casting.unit.health, 0),
            put_in(casting.internal.taxi_flight, %{}),
            put_in(casting.internal.movement_start_time, 1)
          ] do
        assert {^blocked, []} = Knockback.pull(blocked, context, 30.0, 100)
      end
    end
  end

  describe "receive/4" do
    test "routes pull through movement and honors its independent immunity", %{character: character} do
      effect = %Effect{type: :player_pull, index: 0, misc_value: 300, implicit_target_a: :target_enemy}
      spell = Semantics.compile(%Spell{id: 28_266, effects: [effect]})
      context = %CastContext{caster_guid: 2, caster_position: {WorldRef.open(0), -30.0, 0.0, 0.0}}
      {_, events} = SpellEffect.receive(character, context, spell, 100)
      assert Enum.any?(events, &match?(%Effects.Knockback{horizontal_speed: 30.0, cos_angle: -1.0}, &1))

      for {type, launches?} <- [{:player_pull, false}, {:knockback, true}] do
        immunity = %Holder{spell: %Spell{id: 10}, auras: [%AuraData{type: :effect_immunity, misc_value: type}]}
        protected = put_in(character.unit.auras, [immunity])
        {_, events} = SpellEffect.receive(protected, context, spell, 100)
        assert Enum.any?(events, &is_struct(&1, Effects.Knockback)) == launches?
      end
    end

    test "scales DBC speeds and honors effect immunity", %{character: character} do
      effect = %Effect{
        type: :knockback,
        index: 0,
        base_points: 74,
        base_dice: 1,
        die_sides: 1,
        misc_value: 120,
        implicit_target_a: :target_enemy
      }

      spell = Semantics.compile(%Spell{id: 11_019, effects: [effect]})
      context = %CastContext{caster_guid: 2, caster_level: 60, caster_position: {WorldRef.open(0), -10.0, 0.0, 0.0}}
      {_, events} = SpellEffect.receive(character, context, spell, 100)
      assert Enum.any?(events, &match?(%Effects.Knockback{horizontal_speed: 12.0, vertical_speed: 7.0}, &1))

      immunity = %Holder{spell: %Spell{id: 10}, auras: [%AuraData{type: :effect_immunity, misc_value: :knockback}]}
      protected = put_in(character.unit.auras, [immunity])
      {_, events} = SpellEffect.receive(protected, context, spell, 100)
      refute Enum.any?(events, &is_struct(&1, Effects.Knockback))
      assert Enum.any?(events, &is_struct(&1, Effects.SpellLogMiss))
    end
  end

  defp character(_) do
    %{
      character: %Character{
        object: %Object{guid: 1},
        player: %Player{flags: 0},
        unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
      }
    }
  end

  defp holder(id, type), do: %Holder{spell: %Spell{id: id}, caster_guid: 2, auras: [%AuraData{type: type}]}
end
