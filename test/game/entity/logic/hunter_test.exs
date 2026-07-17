defmodule ThistleTea.Game.Entity.Logic.HunterTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Hunter
  alias ThistleTea.Game.Spell

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
      spell = %Spell{name: "Tame Beast"}

      assert Hunter.validate_tame(hunter, spell, %{tameable?: true, level: 20}) == :ok
      assert Hunter.validate_tame(hunter, spell, %{tameable?: false, level: 20}) == {:error, :bad_targets}
      assert Hunter.validate_tame(hunter, spell, %{tameable?: true, level: 21}) == {:error, :bad_targets}

      assert Hunter.validate_tame(%{unit: %{level: 20, summon: 99}}, spell, %{tameable?: true, level: 10}) ==
               {:error, :already_have_summon}
    end
  end

  describe "after_aura/3" do
    test "feign death clears combat and drops every threat reference" do
      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{target: 2, flags: 0},
        internal: %Internal{in_combat: true, threat_refs: MapSet.new([{2, 1}, {3, 1}])}
      }

      {character, events} = Hunter.after_aura(character, %Spell{name: "Feign Death"}, 1_000)

      refute character.internal.in_combat
      assert character.internal.threat_refs == MapSet.new()
      assert Enum.count(events, &(&1.type == :drop_threat)) == 2
      assert Enum.any?(events, &(&1.type == :drop_nearby_threat))
      assert Enum.any?(events, &(&1.type == :attack_stop and &1.target_guid == 2))
    end
  end
end
