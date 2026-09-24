defmodule ThistleTea.Game.Spell.AuraRankTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.AuraRank
  alias ThistleTea.Game.Spell.Effect

  setup [:buff]

  describe "select/3" do
    test "keeps a rank at its ten-level boundary and only selects ancestors", %{spell: spell} do
      middle = %{spell | id: 2, rank: 2, spell_level: 24}
      first = %{spell | id: 1, rank: 1, spell_level: 12}
      assert AuraRank.select(spell, 38, [middle, first]) == spell
      assert AuraRank.select(spell, 37, [middle, first]) == middle
      assert AuraRank.select(spell, 14, [middle, first]) == middle
      assert AuraRank.select(spell, 13, [middle, first]) == first
      assert AuraRank.select(spell, 1, [middle, first]) == nil
      assert AuraRank.select(first, 60, []) == first
    end

    test "unranked, passive, harmful and self-only spells are exempt", %{spell: spell} do
      [effect] = spell.effects

      for exempt <- [
            %{spell | rank: nil},
            %{spell | attributes: MapSet.new([:passive])},
            %{spell | effects: [%{effect | implicit_target_a: :caster}]},
            %{spell | effects: [%{effect | type: :heal}]},
            %{spell | effects: [%{effect | base_points: -10}]},
            %{spell | effects: [%{effect | implicit_target_a: :target_enemy}]},
            %{spell | custom_flags: 0x002}
          ] do
        assert AuraRank.select(exempt, 1, []) == exempt
      end
    end

    test "positive effects retain their level rule in mixed spells", %{spell: spell} do
      mixed = %{spell | effects: spell.effects ++ [%Effect{type: :school_damage, implicit_target_a: :target_enemy}]}
      assert AuraRank.minimum_level(mixed) == 38
    end

    test "persistent party auras are ranked even with a caster target", %{spell: spell} do
      effect = %{hd(spell.effects) | type: :apply_area_aura, implicit_target_a: :caster}
      spell = %{spell | effects: [effect]}
      assert AuraRank.party_aura?(spell)
      assert AuraRank.minimum_level(spell) == 38
    end
  end

  describe "validate/4" do
    test "rejects low-level player targets and accepts the exact boundary", %{spell: spell} do
      assert AuraRank.validate(%Character{}, spell, %{level: 37}, []) == {:error, :lowlevel}
      assert AuraRank.validate(%Character{}, spell, %{level: 38}, []) == :ok
      assert AuraRank.validate(%Character{}, spell, :self, []) == :ok
    end

    test "item, triggered, creature and attribute exceptions skip the level gate", %{spell: spell} do
      assert AuraRank.validate(%Character{}, spell, %{level: 1}, cast_item_guid: 12) == :ok
      assert AuraRank.validate(%Character{}, spell, %{level: 1}, triggered?: true) == :ok
      assert AuraRank.validate(%Mob{}, spell, %{level: 1}, []) == :ok
      spell = %{spell | attributes: MapSet.new([:allow_low_level_buff])}
      assert AuraRank.validate(%Character{}, spell, %{level: 1}, []) == :ok
      assert AuraRank.select(spell, 1, []) == nil
    end
  end

  defp buff(_context) do
    %{
      spell: %Spell{
        id: 3,
        rank: 3,
        spell_level: 48,
        effects: [%Effect{type: :apply_aura, aura: :mod_stat, base_points: 10, implicit_target_a: :target_ally}]
      }
    }
  end
end
