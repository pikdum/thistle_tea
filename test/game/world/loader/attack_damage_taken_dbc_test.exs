defmodule ThistleTea.Game.World.Loader.AttackDamageTakenDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AttackDamageTaken
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "every Stoneskin rank reduces melee damage only" do
      for {id, reduction} <- [{8072, 4}, {8156, 7}, {8157, 11}, {10_403, 16}, {10_404, 22}, {10_405, 30}] do
        spell = SpellLoader.load(id)
        assert Enum.any?(spell.effects, &(&1.aura == :mod_melee_damage_taken))
        {entity, _} = Aura.apply_spell(character(), 1, 60, spell, 0)
        assert AttackDamageTaken.amount(entity, 100, :melee) == 100 - reduction
        assert AttackDamageTaken.amount(entity, 100, :ranged) == 100
      end
    end

    test "creature Shadowform effects reduce melee damage by percentage" do
      for {id, reduction} <- [{16_592, 20}, {22_917, 40}] do
        spell = SpellLoader.load(id)
        assert Enum.any?(spell.effects, &(&1.aura == :mod_melee_damage_taken_pct))
        {entity, _} = Aura.apply_spell(character(), 1, 60, spell, 0)
        assert AttackDamageTaken.amount(entity, 100, :melee) == 100 - reduction
        assert AttackDamageTaken.amount(entity, 100, :ranged) == 100
      end
    end
  end

  defp character do
    %Character{object: %Object{guid: 1}, unit: %Unit{health: 1_000, max_health: 1_000, auras: []}}
  end
end
