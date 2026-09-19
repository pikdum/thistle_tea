defmodule ThistleTea.Game.World.Loader.ResistancePenetrationDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.EquipmentStats
  alias ThistleTea.Game.Entity.Logic.ResistancePenetration
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "scales each Serrated Blades rank with caster level" do
      for {id, level, amount} <- [{14_171, 60, -100}, {14_172, 60, -200}, {14_173, 60, -300}, {14_173, 40, -200}] do
        {caster, _events} = Aura.apply_spell(caster(), 1, level, SpellLoader.load(id), 0)
        assert ResistancePenetration.snapshot(caster) == [{1, amount}]
      end
    end

    test "Bonereaver stacks to three and removes its armor penetration on expiry" do
      spell = SpellLoader.load(21_153)
      caster = Enum.reduce(1..4, caster(), fn at, caster -> elem(Aura.apply_spell(caster, 1, 60, spell, at), 0) end)
      assert ResistancePenetration.snapshot(caster) == [{1, -2_100}]
      {expired, _events} = Aura.tick(caster, 4 + spell.duration_ms)
      assert ResistancePenetration.snapshot(expired) == []
    end

    test "preserves magic school selectors on talents and equipment" do
      for {id, mask, amount} <-
            [
              {11_210, 126, -5},
              {12_592, 126, -10},
              {25_717, 4, -300},
              {25_718, 16, -300},
              {25_975, 124, -10}
            ] do
        spell = SpellLoader.load(id)
        {caster, _events} = Aura.apply_spell(caster(), 1, 60, spell, 0)
        assert ResistancePenetration.snapshot(caster) == [{mask, amount}]
        item = %ItemTemplate{entry: 1, spellid_1: id, spelltrigger_1: 1}
        assert EquipmentStats.bonuses([item], fn ^id -> spell end).resistance_penetration == [{mask, amount}]
      end
    end
  end

  defp caster, do: %Mob{unit: %Unit{health: 1_000, max_health: 1_000, auras: []}}
end
