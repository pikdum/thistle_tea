defmodule ThistleTea.Game.Entity.Logic.DefensiveCapabilitiesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.SpellRemoval
  alias ThistleTea.Game.Player.Spells
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:character]

  describe "defensive_chances/1" do
    test "defense skill adjusts every learned defense", %{character: character} do
      for {skill, chance} <- [{295, 4.8}, {300, 5.0}, {305, 5.2}] do
        character = with_defense(character, skill) |> CombatRatings.sync()
        assert character.player.dodge_percentage == chance
        assert character.player.parry_percentage == chance
        assert character.player.block_percentage == chance
        assert character.player.crit_percentage == 5.0
      end
    end

    test "temporary and permanent skill bonuses stack", %{character: character} do
      holders = [holder(:mod_skill, 5, 95), holder(:mod_skill_talent, 10, 95)]
      character = %{character | unit: %{character.unit | auras: holders}}
      assert CombatRatings.defensive_chances(character) == %{dodge: 5.6, parry: 5.6, block: 5.6}
    end

    test "clamps reduced defense and avoidance at zero", %{character: character} do
      assert character |> with_defense(1) |> CombatRatings.defensive_chances() == %{dodge: 0.0, parry: 0.0, block: 0.0}
    end

    test "weapon removal, breakage and feral forms disable parry", %{character: character} do
      unarmed = %{character | player: %{character.player | visible_item_16_0: 0}}
      broken = %{character | player: %{character.player | broken_equipment: [:mainhand]}}
      assert CombatRatings.parry_chance(unarmed) == 0.0
      assert CombatRatings.parry_chance(broken) == 0.0
      assert CombatRatings.parry_chance(%{broken | unit: %{broken.unit | base_offhand_max_damage: 20}}) == 5.0

      for form <- [1, 5, 8] do
        feral = %{character | unit: %{character.unit | class: 11, shapeshift_form: form}}
        assert CombatRatings.parry_chance(feral) == 0.0
      end
    end
  end

  describe "resolve/4" do
    test "counts defense skill once at each attack-table boundary", %{character: character} do
      for {skill, weapon_skill, chance_bp} <- [{305, 300, 520}, {295, 300, 480}, {305, 310, 480}] do
        target = with_defense(character, skill)
        attack = Map.put(attack(), :caster_attack_skill, weapon_skill)
        assert AttackTable.resolve(target, attack, 100, roll: chance_bp - 1).outcome == :miss
        assert AttackTable.resolve(target, attack, 100, roll: chance_bp).outcome == :dodge
        assert AttackTable.resolve(target, attack, 100, roll: 2 * chance_bp - 1).outcome == :dodge
        assert AttackTable.resolve(target, attack, 100, roll: 2 * chance_bp).outcome == :parry
        assert AttackTable.resolve(target, attack, 100, roll: 3 * chance_bp - 1).outcome == :parry
        assert AttackTable.resolve(target, attack, 100, roll: 3 * chance_bp).outcome == :block
        assert AttackTable.resolve(target, attack, 100, roll: 4 * chance_bp - 1).outcome == :block
        assert AttackTable.resolve(target, attack, 100, roll: 4 * chance_bp).outcome in [:normal, :crit]
        assert AttackTable.roll_special(target, attack, roll: 3 * chance_bp).outcome == :block
      end
    end

    test "weak opponents and avoidance auras cannot grant unlearned abilities", %{character: character} do
      character = %{
        character
        | internal: %Internal{},
          unit: %{character.unit | auras: [holder(:mod_parry_percent, 50), holder(:mod_block_percent, 50)]}
      }

      for class <- [1, 7], roll <- [1_000, 2_000, 5_000] do
        target = %{character | unit: %{character.unit | class: class}}
        attack = %{attack() | caster_level: 50, caster_attack_skill: 250}
        refute AttackTable.resolve(target, attack, 100, roll: roll).outcome in [:parry, :block]
      end
    end

    test "sheathed weapons prevent blocks but retain character-sheet chances", %{character: character} do
      for sheath <- [0, 1, 2] do
        character = %{character | unit: %{character.unit | sheath_state: sheath}}
        assert CombatRatings.block_chance(character) == 5.0
        expected = if sheath == 0, do: :normal, else: :block
        assert AttackTable.resolve(character, attack(), 100, roll: 1_600).outcome == expected
      end
    end

    test "creature avoidance includes aura modifiers and the block cap", %{character: character} do
      unit = %{
        character.unit
        | auras: [holder(:mod_dodge, 2), holder(:mod_parry_percent, 3), holder(:mod_block_percent, 50)]
      }

      mob = %Mob{unit: unit, internal: %Internal{}}
      assert AttackTable.resolve(mob, attack(), 100, roll: 1_199).outcome == :dodge
      assert AttackTable.resolve(mob, attack(), 100, roll: 1_200).outcome == :parry
      assert AttackTable.resolve(mob, attack(), 100, roll: 1_999).outcome == :parry
      assert AttackTable.resolve(mob, attack(), 100, roll: 2_000).outcome == :block
      assert AttackTable.resolve(mob, attack(), 100, roll: 2_500).outcome == :normal
    end
  end

  describe "apply_passives/2 and remove/3" do
    test "learn and unlearn refresh capabilities without aura changes", %{character: character} do
      learned = Spells.apply_passives(character, 0)
      assert learned.unit.auras == []
      assert learned.player.parry_percentage == 5.0
      assert learned.player.block_percentage == 5.0
      removed = SpellRemoval.remove(learned, [3127, 107], 1)
      assert removed.player.parry_percentage == 0.0
      assert removed.player.block_percentage == 0.0
      assert removed.player.dodge_percentage == 5.0
      assert removed.internal.spells == []
      assert removed.internal.spellbook == %{}
      restored = Spells.apply_passives(%{removed | internal: character.internal}, 2)
      assert restored.player == learned.player
    end
  end

  describe "receive_attack/4" do
    test "defense skill gains immediately refresh displayed avoidance", %{character: character} do
      character = with_defense(character, 295) |> CombatRatings.sync()

      {gained, _events} =
        Combat.receive_attack(character, Map.put(attack(), :damage, 10), 1_000, roll: 0, skill_roll: fn _ -> true end)

      assert gained.player.skills[95].value == 296
      assert_in_delta gained.player.dodge_percentage - character.player.dodge_percentage, 0.04, 0.0001
      assert_in_delta gained.player.parry_percentage - character.player.parry_percentage, 0.04, 0.0001
      assert_in_delta gained.player.block_percentage - character.player.block_percentage, 0.04, 0.0001
    end
  end

  defp character(_context) do
    book = %{
      107 => %Spell{id: 107, effects: [%Effect{type: :block}]},
      3127 => %Spell{id: 3127, effects: [%Effect{type: :parry}]}
    }

    character = %Character{
      object: %Object{guid: 1},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      unit: %Unit{
        health: 1_000,
        max_health: 1_000,
        level: 60,
        class: 1,
        agility: 100,
        sheath_state: 1,
        auras: [],
        equipment_bonuses: %{shields: 1, shield_block: 20}
      },
      player: %Player{visible_item_16_0: 1},
      internal: %Internal{spellbook: book, spells: [107, 3127]}
    }

    %{character: character}
  end

  defp attack, do: %{caster: 2, caster_level: 60, caster_attack_skill: 300, caster_player?: false, crit_chance: 0}

  defp holder(type, amount, misc \\ 0), do: %Holder{auras: [%AuraData{type: type, amount: amount, misc_value: misc}]}

  defp with_defense(character, value) do
    skills = %{95 => %{value: value, max: 300, range: :level, always_max?: false}}
    %{character | player: %{character.player | skills: skills}}
  end
end
