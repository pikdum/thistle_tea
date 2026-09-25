defmodule ThistleTea.Game.World.Loader.SpellAvoidanceDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "loads the native Avoidance passive as a 25-point hit defense" do
      spell = SpellLoader.load(23_198)
      assert Spell.attribute?(spell, :passive)
      assert [%Effect{aura: :mod_aoe_avoidance, base_points: 24}] = spell.effects
      {mob, _} = Aura.apply_spell(%Mob{unit: %Unit{health: 100, max_health: 100}}, 1, 60, spell, 0)
      assert SpellResist.defense_snapshot(mob).aoe_avoidance == 25
    end

    test "classifies bursts, cones, ground spells, and channels from their targets" do
      for id <- [10, 120, 122, 1449, 2120, 26_573] do
        spell = SpellLoader.load(id)
        assert Spell.area_of_effect?(spell), "expected area spell #{spell.name} (#{id})"
        assert spell.semantics.area_of_effect?
        assert Spell.area_of_effect?(%{spell | effects: []})
      end
    end

    test "keeps direct spells, chains, and direct channels outside area avoidance" do
      for id <- [116, 133, 421, 1064, 5143] do
        spell = SpellLoader.load(id)
        refute Spell.area_of_effect?(spell), "unexpected area spell #{spell.name} (#{id})"
      end
    end
  end
end
