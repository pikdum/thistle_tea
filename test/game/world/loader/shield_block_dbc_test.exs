defmodule ThistleTea.Game.World.Loader.ShieldBlockDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "Block and Parry grant combat capabilities while the Shaman talent teaches Parry" do
      block = SpellLoader.load(107)
      parry = SpellLoader.load(3127)
      talent = SpellLoader.load(16_268)
      talent_parry = SpellLoader.load(18_848)
      assert Proficiency.from_spellbook(%{107 => block}).block?
      assert Proficiency.from_spellbook(%{3127 => parry}).parry?
      assert Enum.any?(talent.effects, &(&1.type == :learn_spell and &1.trigger_spell_id == 18_848))
      assert Proficiency.from_spellbook(%{18_848 => talent_parry}).parry?
    end

    test "Shield Specialization ranks scale block value by percentages" do
      for {id, percent} <- [
            {16_253, 5},
            {16_298, 10},
            {16_299, 15},
            {16_300, 20},
            {16_301, 25},
            {20_148, 10},
            {20_149, 20},
            {20_150, 30}
          ] do
        spell = SpellLoader.load(id)
        assert Enum.any?(spell.effects, &(&1.aura == :mod_shield_block_value_pct))
        {character, _} = Aura.apply_spell(character(), 1, 60, spell, 0)
        assert CombatRatings.block_value(character) == trunc(106 * (100 + percent) / 100)
      end
    end

    test "equipment, enchantments and Glyph of Deflection add flat block value" do
      for {id, value} <- [{23_562, 30}, {24_148, 15}, {28_773, 235}] do
        spell = SpellLoader.load(id)
        assert Enum.any?(spell.effects, &(&1.aura == :mod_shield_block_value))
        {character, _} = Aura.apply_spell(character(), 1, 60, spell, 0)
        assert CombatRatings.block_value(character) == 106 + value
      end
    end
  end

  defp character do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{
        health: 1_000,
        max_health: 1_000,
        strength: 140,
        equipment_bonuses: %{shields: 1, shield_block: 100},
        auras: []
      },
      player: %Player{}
    }
  end
end
