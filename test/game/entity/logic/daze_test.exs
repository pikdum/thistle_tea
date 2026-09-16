defmodule ThistleTea.Game.Entity.Logic.DazeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Daze
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  setup [:combatants]

  describe "attacker?/1" do
    test "only uncontrolled creatures qualify", %{mob: mob, character: character} do
      assert Daze.attacker?(mob)
      refute Daze.attacker?(character)
      refute Daze.attacker?(%{mob | internal: %{mob.internal | pet: %Pet{owner_guid: 1}}})
      refute Daze.attacker?(%{mob | unit: %{mob.unit | charmed_by: 1}})
      refute Daze.attacker?(%{mob | unit: %{mob.unit | summoned_by: 1}})
      assert AttackTable.attacker_context(mob).caster_can_daze?
      refute AttackTable.attacker_context(character).caster_can_daze?
    end
  end

  describe "chance/2" do
    test "scales protection with level", %{character: character} do
      for {level, expected} <- [{1, 1.15}, {10, 7.0}, {29, 19.35}, {30, 20.0}, {60, 20.0}] do
        target = %{character | unit: %{character.unit | level: level}, player: %Player{skills: %{}}}
        assert_in_delta Daze.chance(target, %{caster_level: level}), expected, 0.0001
      end
    end

    test "uses learned defense and clamps skill differences", %{character: character, attack: attack} do
      assert Daze.chance(character, attack) == 20.0
      unskilled = %{character | player: %Player{skills: %{95 => %{value: 1}}}}
      assert Daze.chance(unskilled, attack) == 40.0
      assert Daze.chance(character, %{attack | caster_level: 1}) == 0.0
      assert Daze.chance(character, Map.put(attack, :caster_attack_skill, 175)) == 25.0
    end

    test "defense bonuses protect against daze and melee hits", %{character: character, attack: attack} do
      holder = %Holder{
        auras: [
          %Aura{type: :mod_skill, misc_value: 95, amount: 10},
          %Aura{type: :mod_skill_talent, misc_value: 95, amount: 10},
          %Aura{type: :mod_skill, misc_value: 43, amount: 100}
        ]
      }

      defended = %{character | unit: %{character.unit | auras: [holder]}}
      assert Daze.chance(defended, attack) == 16.0
      assert AttackTable.resolve(character, attack, 10, roll: 550).outcome != :miss
      assert AttackTable.resolve(defended, attack, 10, roll: 550).outcome == :miss
    end
  end

  describe "events/4" do
    test "rolls independently and preserves source attribution", %{character: character, attack: attack} do
      assert [%Effects.TriggerSpell{source_guid: 2, target_guid: 1, spell_id: 1604, source_level: 30}] =
               Daze.events(character, attack, 10, fn -> 19.99 end)

      assert Daze.events(character, attack, 10, fn -> 20.0 end) == []
    end

    test "requires a rear melee hit that deals damage", %{character: character, attack: attack} do
      for changes <- [
            %{caster_position: {1.0, 0.0, 0.0}},
            %{caster_position: nil},
            %{caster_can_daze?: false},
            %{ranged?: true}
          ] do
        assert Daze.events(character, Map.merge(attack, changes), 10, fn -> flunk("ineligible roll") end) == []
      end

      assert Daze.events(character, attack, 0, fn -> flunk("zero damage roll") end) == []
    end

    test "protects dead and invincible targets", %{character: character, attack: attack} do
      for target <- [
            %{character | unit: %{character.unit | health: 0}},
            %{character | internal: %{character.internal | godmode: true}},
            %{character | internal: %{character.internal | invincibility_health_threshold: 1}}
          ] do
        assert Daze.events(target, attack, 10, fn -> flunk("protected roll") end) == []
      end
    end

    test "creature victims use level defense", %{mob: mob, attack: attack} do
      assert Daze.chance(mob, attack) == 20.0
      assert [_daze] = Daze.events(mob, %{attack | caster_position: {-2.0, 0.0, 0.0}}, 10, fn -> 0 end)
    end
  end

  describe "receive_attack/4" do
    test "successful rear swings request daze before melee feedback", %{character: character, attack: attack} do
      {target, events} = Combat.receive_attack(character, attack, 1_000, roll: 9_999, daze_roll: fn -> 0 end)
      assert target.unit.health < character.unit.health
      assert [%Effects.TriggerSpell{spell_id: 1604}, %Effects.AttackerStateUpdate{} | _] = events
    end

    test "misses, absorbs, and lethal hits do not daze", %{character: character, attack: attack} do
      shield = %Holder{
        spell: %Spell{id: 17},
        caster_guid: 1,
        auras: [%Aura{type: :school_absorb, amount: 1_000, misc_value: 1}]
      }

      for {target, roll} <- [
            {character, 0},
            {%{character | unit: %{character.unit | auras: [shield]}}, 9_999},
            {%{character | unit: %{character.unit | health: 1}}, 9_999}
          ] do
        {_target, events} = Combat.receive_attack(target, attack, 1_000, roll: roll, daze_roll: fn -> 0 end)
        refute Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 1604}, &1))
      end
    end
  end

  defp combatants(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 30, health: 1_000, max_health: 1_000, auras: []},
      player: %Player{skills: %{95 => %{value: 150, max: 150}}},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    mob = %Mob{
      object: %Object{guid: 2},
      unit: %Unit{level: 30, health: 100, max_health: 100},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {-1.0, 0.0, 0.0, 0.0}}
    }

    attack = mob |> AttackTable.attacker_context() |> Map.merge(%{caster: 2, damage: 10})
    %{character: character, mob: mob, attack: attack}
  end
end
