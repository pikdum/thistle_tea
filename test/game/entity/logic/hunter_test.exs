defmodule ThistleTea.Game.Entity.Logic.HunterTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Hunter
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  describe "validate_ammo/5" do
    test "accepts matching arrows and rejects missing or mismatched projectiles" do
      spell = %Spell{dmg_class: 3}
      bow = %{class: 2, inventory_type: 15, ammo_type: 2}
      arrows = %{class: 6, subclass: 2}
      bullets = %{class: 6, subclass: 3}

      assert Hunter.validate_ammo(spell, 2519, arrows, [bow], fn 2519 -> 20 end) == :ok
      assert Hunter.validate_ammo(spell, 2519, arrows, [bow], fn 2519 -> 0 end) == {:error, :no_ammo}
      assert Hunter.validate_ammo(spell, 2519, bullets, [bow], fn 2519 -> 20 end) == {:error, :no_ammo}
    end

    test "does not require projectiles for thrown weapons or non-ranged spells" do
      thrown = %{class: 2, inventory_type: 25, ammo_type: 0}

      assert Hunter.validate_ammo(%Spell{dmg_class: 3}, nil, nil, [thrown], nil) == :ok
      assert Hunter.validate_ammo(%Spell{dmg_class: 0}, nil, nil, [], nil) == :ok
    end
  end

  describe "ammo_reagents/2" do
    test "consumes one selected projectile per ranged cast" do
      character = %{player: %{ammo_id: 2519}}

      assert Hunter.ammo_reagents(character, %Spell{dmg_class: 3}) == [{2519, 1}]
      assert Hunter.ammo_reagents(character, %Spell{dmg_class: 2}) == []
    end
  end

  describe "validate_tame/3" do
    test "requires a tameable beast at or below the hunter level and no active pet" do
      hunter = %{unit: %{level: 20, summon: 0}}
      spell = %Spell{effects: [%Effect{type: :tame_creature}]}

      assert Hunter.validate_tame(hunter, spell, %{tameable?: true, level: 20}) == :ok
      assert Hunter.validate_tame(hunter, spell, %{tameable?: false, level: 20}) == {:error, :bad_targets}
      assert Hunter.validate_tame(hunter, spell, %{tameable?: true, level: 21}) == {:error, :bad_targets}

      assert Hunter.validate_tame(%{unit: %{level: 20, summon: 99}}, spell, %{tameable?: true, level: 10}) ==
               {:error, :already_have_summon}
    end
  end

  describe "validate_feed/2" do
    test "uses the pet family diet mask and VMangos food level tiers" do
      spell = %Spell{effects: [%Effect{type: :feed_pet, trigger_spell_id: 1539}]}
      pet = %{alive?: true, in_combat: false, food_mask: 0b1, level: 30}

      assert Hunter.validate_feed(spell, %{pet: pet, item: %{food_type: 1, item_level: 25}}) == :ok

      assert Hunter.feed_benefit(%{pet: pet, item: %{food_type: 1, item_level: 25}}) ==
               {:ok, 35_000}

      assert Hunter.food_benefit(30, 20) == 17_000
      assert Hunter.food_benefit(30, 16) == 8_000
      assert Hunter.food_benefit(30, 15) == 0

      assert Hunter.validate_feed(spell, %{pet: pet, item: %{food_type: 2, item_level: 30}}) ==
               {:error, :wrong_pet_food}

      assert Hunter.validate_feed(spell, %{pet: pet, item: %{food_type: 1, item_level: 15}}) ==
               {:error, :food_lowlevel}
    end

    test "rejects missing, dead, and fighting pets" do
      spell = %Spell{effects: [%Effect{type: :feed_pet, trigger_spell_id: 1539}]}
      item = %{food_type: 1, item_level: 20}

      assert Hunter.validate_feed(spell, %{item: item, pet: nil}) == {:error, :no_pet}

      assert Hunter.validate_feed(spell, %{
               item: item,
               pet: %{alive?: false, in_combat: false, food_mask: 1, level: 20}
             }) == {:error, :targets_dead}

      assert Hunter.validate_feed(spell, %{
               item: item,
               pet: %{alive?: true, in_combat: true, food_mask: 1, level: 20}
             }) == {:error, :affecting_combat}
    end

    test "overrides the DBC trigger aura amount without changing unrelated effects" do
      energize = %Effect{index: 0, type: :apply_aura, aura: :periodic_energize, base_points: 9_999, die_sides: 1}
      other = %Effect{index: 1, type: :dummy, base_points: 10}

      spell = Hunter.apply_food_benefit(%Spell{effects: [energize, other]}, 35_000)

      assert [%Effect{base_points: 35_000, die_sides: 0}, ^other] = spell.effects
    end
  end

  describe "after_aura/3" do
    test "feign death clears combat and drops every threat reference" do
      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{target: 2, flags: 0, stand_state: 0},
        internal: %Internal{
          in_combat: true,
          threat_refs: MapSet.new([{2, 1}, {3, 1}]),
          auto_shot: %{target_guid: 2}
        }
      }

      spell = %Spell{effects: [%Effect{type: :apply_aura, aura: :feign_death}]}
      {character, events} = Hunter.after_aura(character, spell, 1_000)

      refute character.internal.in_combat
      assert character.internal.threat_refs == MapSet.new()
      assert character.internal.auto_shot == nil
      assert character.unit.stand_state == 7
      assert Enum.count(events, &(&1.type == :drop_threat)) == 2
      assert Enum.any?(events, &(&1.type == :drop_nearby_threat))
      assert Enum.any?(events, &(&1.type == :attack_stop and &1.target_guid == 2))
      assert Enum.any?(events, &(&1.type == :stand_state and &1.stand_state == 7))
    end
  end
end
