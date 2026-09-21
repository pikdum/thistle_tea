defmodule ThistleTea.Game.Entity.Logic.WeaponBonusesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.CombatSkills
  alias ThistleTea.Game.Entity.Logic.CombatWeapon
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  setup [:armed_character]

  describe "crit_chance/2" do
    @tag :dbc_db
    test "loaded dagger and ranged talents retain their equipment requirements", %{character: character} do
      character =
        Enum.reduce([13_807, 19_431, 13_845], character, fn id, entity ->
          {entity, _events} = ThistleTea.Game.Entity.Logic.Aura.apply_spell(entity, 1, 60, SpellLoader.load(id), 0)
          entity
        end)

      assert character.player.crit_percentage == 5.0
      assert character.player.ranged_crit_percentage == 10.0
      assert CombatRatings.hit_chance(character, :mainhand) == 5
      assert CombatRatings.hit_chance(character, :offhand) == 5
      assert CombatRatings.hit_chance(character, :ranged) == 0

      swapped = %{character | unit: %{character.unit | mainhand_weapon: character.unit.offhand_weapon}}
      assert CombatRatings.crit_chance(swapped, :mainhand) == 10.0
    end

    test "talents follow the main hand and ranged weapon independently", %{character: character} do
      character = with_auras(character, [bonus(:mod_crit_percent, 5, 15), bonus(:mod_crit_percent, 3, 2)])
      assert CombatRatings.crit_chance(character, :mainhand) == 5.0
      assert CombatRatings.crit_chance(character, :offhand) == 5.0
      assert CombatRatings.crit_chance(character, :ranged) == 8.0

      swapped = %{character | unit: %{character.unit | mainhand_weapon: character.unit.offhand_weapon}}
      assert CombatRatings.crit_chance(swapped, :mainhand) == 10.0
      assert CombatRatings.crit_chance(swapped, :offhand) == 10.0
    end

    test "crit enchants apply once from their own weapon", %{character: character} do
      enchant = %{bonus(:mod_crit_percent, 2, 15) | item_source: {102, 1, 22_755}}
      character = with_auras(character, [enchant])
      assert CombatRatings.crit_chance(character, :mainhand) == 7.0
      assert CombatRatings.crit_chance(character, :offhand) == 7.0
      assert CombatRatings.crit_chance(character, :ranged) == 5.0

      stale = with_auras(character, [%{enchant | item_source: {999, 1, 22_755}}])
      assert CombatRatings.crit_chance(stale, :mainhand) == 5.0

      broken = %{character | player: %{character.player | broken_equipment: [:offhand]}}
      assert CombatRatings.crit_chance(broken, :mainhand) == 5.0
    end

    test "item requirements include inventory type", %{character: character} do
      talent = bonus(:mod_crit_percent, 5, 7)
      talent = %{talent | spell: %{talent.spell | equipped_item_inventory_type_mask: Bitwise.bsl(1, 17)}}
      character = with_auras(character, [talent])
      assert CombatRatings.crit_chance(character, :mainhand) == 5.0
    end

    test "generic crit stacks apply to both channels", %{character: character} do
      generic = %{bonus(:mod_crit_percent, 2, nil) | stacks: 2}
      character = with_auras(character, [generic])
      assert CombatRatings.crit_chance(character, :mainhand) == 9.0
      assert CombatRatings.crit_chance(character, :ranged) == 9.0
    end

    test "disarm removes mainhand talents while retaining an offhand enchant", %{character: character} do
      enchant = %{bonus(:mod_crit_percent, 2, 15) | item_source: {102, 1, 22_755}}
      character = with_auras(character, [bonus(:mod_crit_percent, 5, 7), enchant, bonus(:mod_disarm, 0, nil)])
      assert CombatRatings.crit_chance(character, :mainhand) == 7.0
      assert CombatWeapon.usable(character, :mainhand) == nil
      assert CombatWeapon.usable(character, :offhand) == character.unit.offhand_weapon
    end

    test "feral forms suppress weapon bonuses and use maximum mainhand skill", %{character: character} do
      character = with_auras(character, [bonus(:mod_crit_percent, 5, 7), bonus(:mod_crit_percent, 3, nil)])

      for form <- [1, 5, 8] do
        shifted = %{character | unit: %{character.unit | shapeshift_form: form}}
        assert CombatRatings.crit_chance(shifted, :mainhand) == 8.0
        assert CombatSkills.snapshot(shifted, :offhand).caster_attack_skill == 0
        assert CombatSkills.snapshot(shifted, :ranged).caster_attack_skill == 0
      end
    end
  end

  describe "sync/1" do
    test "weapon skill and skill bonuses update displayed and outgoing crit", %{character: character} do
      sword_skill = %{value: 250, max: 300, range: :level, always_max?: false}
      character = %{character | player: %{character.player | skills: %{43 => sword_skill, 45 => %{value: 275}}}}
      character = with_auras(character, [skill_bonus(:mod_skill, 3), skill_bonus(:mod_skill_talent, 2)])
      character = CombatRatings.sync(character)
      assert_in_delta character.player.crit_percentage, 3.2, 0.0001
      assert character.player.ranged_crit_percentage == 4.0
      assert AttackTable.attacker_context(character).crit_chance == character.player.crit_percentage

      trained = CombatSkills.advance(character, 43, roll: fn _ -> true end)
      assert_in_delta trained.player.crit_percentage, 3.24, 0.0001
    end

    test "missing ranged weapons and low skills clamp displayed crit to zero", %{character: character} do
      character = %{
        character
        | unit: %{character.unit | ranged_weapon: nil},
          player: %{character.player | skills: %{43 => %{value: 1}}}
      }

      character = CombatRatings.sync(character)
      assert character.player.crit_percentage == 0.0
      assert character.player.ranged_crit_percentage == 0.0
    end
  end

  describe "hit_chance/2" do
    test "hit talents retain equipped identity through disarm, breakage, and forms", %{character: character} do
      character = with_auras(character, [bonus(:mod_hit_chance, 5, 7), bonus(:mod_disarm, 0, nil)])
      assert CombatRatings.hit_chance(character, :mainhand) == 5

      broken = %{character | player: %{character.player | broken_equipment: [:mainhand]}}
      assert CombatRatings.hit_chance(broken, :mainhand) == 5

      shifted = %{character | unit: %{character.unit | shapeshift_form: 1}}
      assert CombatRatings.hit_chance(shifted, :mainhand) == 5

      unequipped = %{character | unit: %{character.unit | mainhand_weapon: nil}}
      assert CombatRatings.hit_chance(unequipped, :mainhand) == 0
    end

    test "hit follows the attacking hand in white attacks and spell snapshots", %{character: character} do
      character =
        with_auras(character, [
          bonus(:mod_hit_chance, 5, 15),
          bonus(:mod_hit_chance, 3, 2),
          bonus(:mod_hit_chance, 1, nil)
        ])

      assert AttackTable.attacker_context(character, :mainhand).hit_chance_bonus == 1
      assert AttackTable.attacker_context(character, :offhand).hit_chance_bonus == 6
      assert CombatRatings.hit_chance(character, :ranged) == 4
      assert CastContext.from_caster(character, %Spell{id: 1, dmg_class: 2, school: :physical}, 2).hit_chance_bonus == 1
      assert CastContext.from_caster(character, %Spell{id: 2, dmg_class: 3, school: :physical}, 2).hit_chance_bonus == 4
    end

    test "offhand scope source does not substitute for the attacking weapon requirements", %{character: character} do
      scope = %{bonus(:mod_hit_chance, 3, 2) | item_source: {103, 0, 22_780}}
      character = with_auras(character, [scope])
      assert CombatRatings.hit_chance(character, :mainhand) == 0
      assert CombatRatings.hit_chance(character, :ranged) == 3
    end
  end

  describe "from_caster/3" do
    test "spell snapshots use canonical crit inputs even if client fields are stale", %{character: character} do
      character = with_auras(character, [bonus(:mod_crit_percent, 5, 7), bonus(:mod_crit_percent, 3, 2)])
      character = %{character | player: %{character.player | crit_percentage: 99.0, ranged_crit_percentage: 99.0}}
      melee = CastContext.from_caster(character, %Spell{id: 1, dmg_class: 2, school: :physical}, 2)
      ranged = CastContext.from_caster(character, %Spell{id: 2, dmg_class: 3, school: :physical}, 2)
      assert melee.melee_crit_chance == 10.0
      assert ranged.melee_crit_chance == 8.0
      assert ranged.spell_crit_chance == 8.0
    end
  end

  describe "damage_range/1 and offhand_damage_range/1" do
    test "weapon restrictions filter flat and percentage damage for each hand", %{character: character} do
      character = with_auras(character, [bonus(:mod_damage_percent_done, 50, 15), bonus(:mod_damage_done, 4, 7)])
      assert Combat.damage_range(character) == {104.0, 104.0}
      assert Combat.offhand_damage_range(character) == {75.0, 75.0}
      multipliers = AttackTable.attacker_context(character).attack_damage_multipliers
      assert multipliers.mainhand == 1.0
      assert multipliers.offhand == 0.75
    end

    test "offhand penalties also scale flat damage bonuses", %{character: character} do
      character = with_auras(character, [bonus(:mod_damage_done, 4, 15)])
      assert Combat.damage_range(character) == {100.0, 100.0}
      assert Combat.offhand_damage_range(character) == {52.0, 52.0}
    end
  end

  defp armed_character(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{
        class: 1,
        level: 60,
        agility: 100,
        mainhand_weapon: weapon(7),
        offhand_weapon: weapon(15),
        ranged_weapon: weapon(2),
        min_damage: 100.0,
        max_damage: 100.0,
        min_offhand_damage: 100.0,
        max_offhand_damage: 100.0
      },
      player: %Player{mainhand: 101, offhand: 102, ranged: 103},
      internal: %Internal{}
    }

    %{character: character}
  end

  defp weapon(subclass), do: %ItemTemplate{class: 2, subclass: subclass, inventory_type: 13}

  defp with_auras(character, holders), do: %{character | unit: %{character.unit | auras: holders}}

  defp bonus(type, amount, subclass) do
    spell = %Spell{
      id: 1,
      equipped_item_class: if(is_nil(subclass), do: -1, else: 2),
      equipped_item_subclass_mask: if(is_nil(subclass), do: 0, else: Bitwise.bsl(1, subclass))
    }

    %Holder{spell: spell, auras: [%Aura{type: type, amount: amount, misc_value: 1}]}
  end

  defp skill_bonus(type, amount) do
    %Holder{spell: %Spell{id: 2}, auras: [%Aura{type: type, amount: amount, misc_value: 43}]}
  end
end
