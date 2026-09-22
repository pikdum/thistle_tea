defmodule ThistleTea.Game.World.Loader.StackingProcDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Proc
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  setup do
    %{caster: %Mob{object: %Object{guid: 1}, unit: %Unit{level: 60, auras: []}, internal: %Internal{}}}
  end

  describe "load/1" do
    test "Unstable Power uses the supported build's twelve damage and healing stacks", %{caster: caster} do
      parent = SpellLoader.load(24_658)
      bonus = %{SpellLoader.load(24_659) | proc_rule: %ProcRule{proc_ex: 0x80000}}
      assert parent.duration_ms == 20_000
      assert bonus.stack_amount == 12
      {caster, events} = Aura.apply_spell(caster, 1, 60, parent, 0)
      assert [%Effects.TriggerSpell{spell_id: 24_659, target_guid: 1}] = events
      {caster, _} = Aura.apply_spell(caster, 1, 60, bonus, 0)
      spell = SpellLoader.load(133)
      context = CastContext.from_caster(caster, spell, 2)
      assert context.spell_damage_bonus.fire == 204
      assert context.healing_bonus == 408

      for id <- [133, 116, 2050, 139, 172, 1449, 3599, 5394, 1535, 8190] do
        spell = SpellLoader.load(id)
        {spent, _} = react(caster, spell)
        assert Enum.find(spent.unit.auras, &(&1.spell.id == 24_659)).stacks == 11, "spell #{id}"
      end

      {unchanged, _} = react(caster, SpellLoader.load(1459))
      assert Enum.find(unchanged.unit.auras, &(&1.spell.id == 24_659)).stacks == 12
    end

    test "Ascendance has six scripted charges and a permanent five-stack bonus", %{caster: caster} do
      parent = %{SpellLoader.load(28_200) | proc_rule: %ProcRule{proc_ex: 0x80000}}
      bonus = SpellLoader.load(28_204)
      assert parent.proc_charges == 0
      assert parent.duration_ms == 20_000
      assert bonus.duration_ms == -1
      assert bonus.stack_amount == 5
      {caster, _} = Aura.apply_spell(caster, 1, 60, parent, 0)
      assert hd(caster.unit.auras).charges == 6
      {caster, events} = react(caster, SpellLoader.load(139))
      assert [%Effects.TriggerSpell{spell_id: 28_204, target_guid: 1}] = events
      {caster, _} = Aura.apply_spell(caster, 1, 60, bonus, 1_000)
      context = CastContext.from_caster(caster, SpellLoader.load(133), 2)
      assert context.spell_damage_bonus.fire == 40
      assert context.healing_bonus == 75

      for id <- [1449, 10, 596] do
        {unchanged, events} = react(caster, SpellLoader.load(id))
        assert unchanged == caster
        assert events == []
      end
    end
  end

  defp react(caster, spell) do
    Aura.reactions(caster, :spell_cast_completed, %{
      spell: spell,
      proc_type: Proc.cast_type(spell),
      outcome: :cast_end,
      victim_guid: 2,
      now: 1_000
    })
  end
end
