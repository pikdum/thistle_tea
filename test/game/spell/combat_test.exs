defmodule ThistleTea.Game.Spell.CombatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Combat
  alias ThistleTea.Game.Spell.Effect

  setup do
    %{
      spell: %Spell{id: 1, effects: [%Effect{type: :school_damage, implicit_target_a: :target_enemy}]},
      context: %CastContext{}
    }
  end

  describe "decide/4" do
    test "only detected misses enter combat and flag PvP", %{spell: spell, context: context} do
      for outcome <- [:miss, :resist, :dodge, :parry, :block, :immune] do
        assert %Combat{combat?: true, pvp?: true, break_stealth?: false} = Combat.decide(spell, context, outcome, true)
        assert Combat.decide(spell, context, outcome, false) == %Combat{}
      end

      assert Combat.decide(spell, context, :reflect, true) == %Combat{}
    end

    test "failure-breaks-stealth overrides concealment and no-threat", %{spell: spell, context: context} do
      spell = %{spell | attributes: MapSet.new([:failure_breaks_stealth, :no_threat])}
      assert %Combat{combat?: true, pvp?: true, break_stealth?: true} = Combat.decide(spell, context, :resist, false)
    end

    test "successful Sap remains peaceful while a detected failure provokes", %{spell: spell, context: context} do
      sap = %{
        spell
        | spell_family: 8,
          family_flags_0: 0x80,
          attributes: MapSet.new([:not_in_combat, :only_peaceful_targets])
      }

      assert Combat.decide(sap, context, :hit, true) == %Combat{}
      assert Combat.decide(sap, context, :immune, false) == %Combat{}
      assert Combat.decide(sap, context, :immune, true).combat?
    end

    test "no initial threat applies only to successful hits", %{spell: spell, context: context} do
      spell = %{spell | attributes: MapSet.new([:no_initial_threat])}
      refute Combat.decide(spell, context, :hit, true).combat?
      assert Combat.decide(spell, context, :immune, true).combat?
    end

    test "instant aura triggers do not engage unless a hit directly increases threat", %{spell: spell} do
      context = %CastContext{triggered_by_aura?: true}
      refute Combat.decide(spell, context, :hit, true).combat?
      refute Combat.decide(spell, context, :resist, true).combat?
      assert Combat.decide(%{spell | speed: 20.0}, context, :resist, true).combat?
      threat = %{spell | effects: [%Effect{type: :modify_threat, base_points: 10, implicit_target_a: :target_enemy}]}
      assert Combat.decide(threat, context, :hit, true).combat?
      refute Combat.decide(threat, context, :resist, true).combat?
    end

    test "a direct triggered cast retains ordinary combat behavior", %{spell: spell} do
      assert Combat.decide(spell, %CastContext{triggered?: true}, :hit, true).combat?
    end

    test "stealth and invisibility have independent successful-hit exemptions", %{spell: spell, context: context} do
      assert %Combat{break_stealth?: true, break_invisibility?: true} = Combat.decide(spell, context, :hit, true)
      spell = %{spell | attributes: MapSet.new([:allow_while_stealthed, :allow_while_invisible])}

      assert %Combat{combat?: true, break_stealth?: false, break_invisibility?: false} =
               Combat.decide(spell, context, :hit, true)
    end

    test "combat-free PvP enabling requires detection on a miss", %{spell: spell, context: context} do
      spell = %{spell | attributes: MapSet.new([:no_threat, :pvp_enabling])}
      assert %Combat{combat?: false, pvp?: true} = Combat.decide(spell, context, :resist, true)
      assert Combat.decide(spell, context, :resist, false) == %Combat{}
    end
  end

  describe "damage_contact?/3" do
    test "only channeled periodic damage initiates combat", %{spell: spell} do
      refute Combat.damage_contact?(spell, true, false)
      assert Combat.damage_contact?(%{spell | attributes: MapSet.new([:channeled])}, true, false)
      assert Combat.damage_contact?(nil, false, false)
    end

    test "proc-triggered spells and damage shields do not initiate combat", %{spell: spell} do
      refute Combat.damage_contact?(spell, false, true)
      assert Combat.damage_contact?(%{spell | attributes: MapSet.new([:not_a_proc])}, false, true)
      shield = %{spell | effects: [%Effect{type: :apply_aura, aura: :damage_shield}]}
      refute Combat.damage_contact?(shield, false, false)
    end
  end
end
