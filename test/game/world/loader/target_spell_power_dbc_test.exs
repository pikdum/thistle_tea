defmodule ThistleTea.Game.World.Loader.TargetSpellPowerDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.EquipmentStats
  alias ThistleTea.Game.Entity.Logic.TargetSpellPower
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "loads creature-specific spell power for slaying gear and consumables" do
      for {id, types, amount} <- [
            {21_010, [6], 14},
            {21_011, [3], 14},
            {22_849, [6], 35},
            {24_197, [6], 48},
            {24_198, [6], 48},
            {28_876, [6], 26},
            {28_890, [6], 60},
            {29_113, [3, 6], 85}
          ] do
        spell = SpellLoader.load(id)
        caster = %Mob{unit: %Unit{health: 1_000, max_health: 1_000, auras: []}}
        {caster, _events} = Aura.apply_spell(caster, 1, 60, spell, 0)
        context = %CastContext{spell_damage_versus: TargetSpellPower.snapshot(caster)}

        for type <- 1..9 do
          target = %{caster | internal: %Internal{creature: %Creature{creature_type: type}}}

          assert TargetSpellPower.benefit(target, context, %Spell{school: :shadow}) ==
                   if(type in types, do: amount, else: 0)
        end
      end
    end

    test "Rune of the Dawn contributes conditional equipment power only" do
      item = %ItemTemplate{entry: 19_812, spellid_1: 24_198, spelltrigger_1: 1}
      bonuses = EquipmentStats.bonuses([item], &SpellLoader.load/1)
      assert bonuses.spell_damage_versus == [{32, 48}]
      assert bonuses.spell_shadow == 0
      assert bonuses.healing == 0
    end
  end
end
