defmodule ThistleTea.Game.Core.Spell.CasterLocationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CasterLocation
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellTarget
  alias ThistleTea.Game.Core.Spell.Target

  describe "destination/3" do
    test "rotates compass offsets with the caster" do
      diagonal = :math.sqrt(50)

      for {selector, {dx, dy}} <- [
            caster_front: {10.0, 0.0},
            caster_back: {-10.0, 0.0},
            caster_left: {0.0, 10.0},
            caster_right: {0.0, -10.0},
            caster_front_right: {diagonal, -diagonal},
            caster_back_right: {-diagonal, -diagonal},
            caster_back_left: {-diagonal, diagonal},
            caster_front_left: {diagonal, diagonal},
            minion_position: {diagonal, diagonal}
          ] do
        effect = %Effect{implicit_target_a: selector, radius_yards: 10.0}
        {x, y, z} = CasterLocation.destination(effect, {20.0, 30.0, 40.0, :math.pi() / 2})
        assert_in_delta x, 20.0 - dy, 0.00001
        assert_in_delta y, 30.0 + dx, 0.00001
        assert z == 40.0
      end
    end

    test "uses secondary selectors and modified effect radii" do
      effect = %Effect{implicit_target_a: :caster, implicit_target_b: :caster_back, radius_yards: 10.0}
      modifiers = [%Aura{type: :add_pct_modifier, misc_value: 6, amount: 50}]
      {x, y, z} = CasterLocation.destination(effect, {20.0, 30.0, 40.0, 0.0}, modifiers)
      assert_in_delta x, 5.0, 0.00001
      assert_in_delta y, 30.0, 0.00001
      assert z == 40.0

      assert CasterLocation.destination(%{effect | radius_yards: nil}, {20.0, 30.0, 40.0, 0.0}) == {20.0, 30.0, 40.0}

      flat = [%Aura{type: :add_flat_modifier, misc_value: 6, amount: 5}]

      assert CasterLocation.destination(%{effect | radius_yards: nil}, {20.0, 30.0, 40.0, 0.0}, flat) ==
               {20.0, 30.0, 40.0}
    end

    test "excludes duel flags and the movement-specific forward leap" do
      for effect <- [%Effect{type: :duel, implicit_target_b: :minion_position}, %Effect{implicit_target_b: 55}] do
        refute CasterLocation.required?(effect)
        assert CasterLocation.destination(effect, {0.0, 0.0, 0.0, 0.0}) == nil
      end
    end
  end

  describe "caster_only?/1" do
    test "ignores unrelated selections while retaining explicit unit and area recipients" do
      effect = %Effect{type: :leap, implicit_target_a: :caster, implicit_target_b: :caster_back, radius_yards: 10.0}
      spell = %Spell{effects: [effect]}
      assert CasterLocation.caster_only?(effect)
      assert SpellTarget.target_query(spell, Target.unit(2)) == :caster

      effect = %{effect | implicit_target_a: :target_enemy}
      refute CasterLocation.caster_only?(effect)
      assert SpellTarget.target_query(%{spell | effects: [effect]}, Target.unit(2)) == {:unit, 2}

      effect = %{effect | implicit_target_a: :aoe_enemy_at_dest}
      refute CasterLocation.caster_only?(effect)

      assert SpellTarget.target_query(%{spell | effects: [effect]}, Target.at({1.0, 2.0, 3.0})) ==
               {:targeted_aoe, {1.0, 2.0, 3.0}, 10.0}
    end
  end
end
