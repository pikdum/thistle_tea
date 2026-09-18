defmodule ThistleTea.Game.World.Loader.EmpathyDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Empathy
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "Beast Lore grants temporary caster access and only targets beasts" do
      spell = SpellLoader.load(1462)
      assert spell.name == "Beast Lore"
      assert spell.duration_ms == 30_000
      assert Spell.creature_type_allowed?(spell, 1)
      refute Spell.creature_type_allowed?(spell, 7)
      entity = %Mob{unit: %Unit{health: 100, auras: []}}

      {active, _events} = Aura.apply_spell(entity, 2, 60, spell, 1_000)
      assert Empathy.visible_to?(active.unit, 2)
      refute Empathy.visible_to?(active.unit, 3)
      assert active.unit.dynamic_flags == 0x10

      {expired, _events} = Aura.expire_due(active, 31_000)
      refute Empathy.visible_to?(expired.unit, 2)
      assert expired.unit.dynamic_flags == 0
    end
  end
end
