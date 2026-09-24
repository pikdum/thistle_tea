defmodule ThistleTea.Game.World.Loader.SpellAuraModifiersDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "Improved Seal of the Crusader increases attack power without changing haste" do
      target = apply_with_talent(20_337, 20_308)
      assert amount(target, :mod_attack_power) == 373.75
      assert amount(target, :mod_attack_speed) == 40
      assert target.unit.attack_power == 573
      assert target.unit.base_attack_time == 1_428
    end

    test "Improved Enslave Demon reduces both slow penalties" do
      target = apply_with_talent(18_825, 1098)
      assert amount(target, :mod_melee_haste) == -30
      assert amount(target, :mod_casting_speed) == -20
      assert target.unit.base_attack_time == 2_600
      assert target.unit.mod_cast_speed == 1.2
    end

    test "Bonescythe Breastplate improves Slice and Dice haste" do
      target = apply_with_talent(28_107, 6774)
      assert amount(target, :mod_melee_haste) == 31.8
      assert target.unit.base_attack_time == trunc(2_000 * 100 / 131.8)
    end

    test "profession casts retain the tradeskill exemption from casting haste" do
      assert Spell.attribute?(SpellLoader.load(10_097), :tradeskill)
      refute Spell.attribute?(SpellLoader.load(133), :tradeskill)
    end
  end

  defp apply_with_talent(talent_id, spell_id) do
    caster = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, base_attack_power: 200, base_melee_attack_time: 2_000, auras: []},
      movement_block: %MovementBlock{movement_flags: 0},
      internal: %Internal{}
    }

    {talented, _events} = Aura.apply_spell(caster, 1, 60, SpellLoader.load(talent_id), 0)
    spell = SpellLoader.load(spell_id)
    context = CastContext.from_caster(talented, spell, 2)
    {target, _events} = Aura.apply_spell(%{caster | object: %Object{guid: 2}}, context, spell, 1_000)
    target
  end

  defp amount(target, type) do
    target.unit.auras |> Enum.flat_map(& &1.auras) |> Enum.find_value(&if(&1.type == type, do: &1.amount))
  end
end
